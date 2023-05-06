module dex::core {
  use std::ascii::{String}; 
  use std::vector;

  use sui::tx_context::{Self, TxContext};
  use sui::coin::{Self, Coin, CoinMetadata};
  use sui::balance::{Self, Supply, Balance};
  use sui::object::{Self,UID, ID};
  use sui::transfer;
  use sui::math;
  use sui::object_bag::{Self, ObjectBag};
  use sui::event;
  use sui::clock::{Self, Clock};
  use sui::pay;

  use dex::curve::{is_curve, is_volatile, Stable, Volatile};
  
  use library::utils;
  use library::math::{mul_div, sqrt_u256};

  const MINIMUM_LIQUIDITY: u64 = 100;
  const PRECISION: u256 = 1000000000000000000; //1e18;
  const VOLATILE_FEE_PERCENT: u256 = 3000000000000000; //0.3%
  const STABLE_FEE_PERCENT: u256 = 500000000000000; //0.05%
  const FLASH_LOAN_FEE_PERCENT: u256 = 5000000000000000; //0.5% 
  const WINDOW: u64 = 900000; // 15 minutes in Milliseconds
  const PERIOD_SIZE: u64 = 180000; // 3 minutes in Milliseconds
  const GRANULARITY: u64 = 5; // 5 updates every 15 minutes

  const ERROR_CREATE_PAIR_ZERO_VALUE: u64 = 1;
  const ERROR_POOL_EXISTS: u64 = 2;
  const ERROR_ZERO_VALUE_SWAP: u64 = 3;
  const ERROR_UNSORTED_COINS: u64 = 4;
  const ERROR_SLIPPAGE: u64 = 5;
  const ERROR_ADD_LIQUIDITY_ZERO_AMOUNT: u64 = 6;
  const ERROR_REMOVE_LIQUIDITY_ZERO_AMOUNT: u64 = 7;
  const ERROR_REMOVE_LIQUIDITY_X_AMOUNT: u64 = 8;
  const ERROR_REMOVE_LIQUIDITY_Y_AMOUNT: u64 = 9;
  const ERROR_NOT_ENOUGH_LIQUIDITY_TO_LEND: u64 = 10;
  const ERROR_WRONG_POOL: u64 = 11;
  const ERROR_WRONG_REPAY_AMOUNT_X: u64 = 12;
  const ERROR_WRONG_REPAY_AMOUNT_Y: u64 = 13;
  const ERROR_WRONG_CURVE: u64 = 14;
  const ERROR_MISSING_OBSERVATION: u64 = 15;
  const ERROR_NO_ZERO_ADDRESS: u64 = 16;
  const ERROR_INVALID_K: u64 = 17;
  const ERROR_POOL_IS_LOCKED: u64 = 18;

    struct DEXAdminCap has key {
      id: UID,
    }

    struct DEXStorage has key {
      id: UID,
      pools: ObjectBag,
      fee_to: address
    }

    struct LPCoin<phantom C, phantom X, phantom Y> has drop {}

    struct Observation has store {
      timestamp: u64,
      balance_x_cumulative: u256,
      balance_y_cumulative: u256
    }

    struct Pool<phantom C, phantom X, phantom Y> has key, store {
        id: UID,
        k_last: u256,
        lp_coin_supply: Supply<LPCoin<C, X, Y>>,
        balance_x: Balance<X>,
        balance_y: Balance<Y>,
        decimals_x: u64,
        decimals_y: u64,
        is_stable: bool,
        observations: vector<Observation>,
        timestamp_last: u64,
        balance_x_cumulative_last: u256,
        balance_y_cumulative_last: u256,
        locked: bool
    }

    // Important this struct cannot have any type abilities
    struct Receipt<phantom C, phantom X, phantom Y> {
      pool_id: ID,
      repay_amount_x: u64,
      repay_amount_y: u64,
      prev_k: u256
    }

    // Events
    struct PoolCreated<phantom P> has copy, drop {
      id: ID,
      shares: u64,
      value_x: u64,
      value_y: u64,
      sender: address
    }

    struct SwapTokenX<phantom C, phantom X, phantom Y> has copy, drop {
      id: ID,
      sender: address,
      coin_x_in: u64,
      coin_y_out: u64
    }

    struct SwapTokenY<phantom C, phantom X, phantom Y> has copy, drop {
      id: ID,
      sender: address,
      coin_y_in: u64,
      coin_x_out: u64
    }

    struct AddLiquidity<phantom P> has copy, drop {
      id: ID,
      sender: address,
      coin_x_amount: u64,
      coin_y_amount: u64,
      shares_minted: u64
    }

    struct RemoveLiquidity<phantom P> has copy, drop {
      id: ID,
      sender: address,
      coin_x_out: u64,
      coin_y_out: u64,
      shares_destroyed: u64
    }

    struct NewAdmin has copy, drop {
      admin: address
    }

    struct NewFeeTo has copy, drop {
      fee_to: address
    }

    /**
    * @dev It gives the caller the VolatileDEXAdminCap object. The VolatileDEXAdminCap allows the holder to update the fee_to key. 
    * It shares the Storage object with the Sui Network.
    */
    fun init(ctx: &mut TxContext) {
      // Give administrator capabilities to the deployer
      // He has the ability to update the fee_to key on the Storage
      transfer::transfer(
        DEXAdminCap { 
          id: object::new(ctx)
        }, 
        tx_context::sender(ctx)
        );

      // Share the DEXStorage object
      transfer::share_object(
         DEXStorage {
           id: object::new(ctx),
           pools: object_bag::new(ctx),
           fee_to: @treasury
         }
      );
    }

    /**
    * @notice The zero address receives a small amount of shares to prevent zero divisions in the future. 
    * @notice Please make sure that the tokens X and Y are sorted before calling this fn.
    * @dev It creates a new Pool with X and Y coins. The pool accepts swaps using the k = x * y invariant.
    * @param storage the object that stores the pools object_bag
    * @param clock_object The shared Clock object 0x6
    * @oaram coin_x the first token of the pool
    * @param coin_y the scond token of the pool
    * @return The number of shares as LPCoins that can be used later on to redeem his coins + commissions.
    * Requirements: 
    * - It will throw if the X and Y are not sorted.
    * - Both coins must have a value greater than 0. 
    * - The pool has a maximum capacity to prevent overflows.
    * - There can only be one pool per each token pair, regardless of their order.
    */
    public fun create_v_pool<X, Y>(
      storage: &mut DEXStorage,
      clock_object: &Clock,
      coin_x: Coin<X>,
      coin_y: Coin<Y>,
      ctx: &mut TxContext
    ): Coin<LPCoin<Volatile, X, Y>> {
      // decimals are not used in the Volatile curve calculation
      create_pool<Volatile, X, Y>(storage, clock_object, coin_x, coin_y, 0, 0, false, ctx)
    }

  /**
    * @notice Please make sure that the tokens X and Y are sorted before calling this fn.
    * @dev It creates a new Pool with X and Y coins. The pool accepts swaps using the x^3y+y^3x >= k invariant.
    * @param storage the object that stores the pools object_bag
    * @param clock_object The shared Clock object 0x6
    * @oaram coin_x the first token of the pool
    * @param coin_y the scond token of the pool
    * @param coin_x_metadata The CoinMetadata object of Coin<X>
    * @param coin_y_metadata The CoinMetadata object of Coin<Y>
    * @return The number of shares as LPCoins that can be used later on to redeem his coins + commissions.
    * Requirements: 
    * - It will throw if the X and Y are not sorted.
    * - Both coins must have a value greater than 0. 
    * - The pool has a maximum capacity to prevent overflows.
    * - There can only be one pool per each token pair, regardless of their order.
    */
    public fun create_s_pool<X, Y>(
      storage: &mut DEXStorage,
      clock_object: &Clock,
      coin_x: Coin<X>,
      coin_y: Coin<Y>,
      coin_x_metadata: &CoinMetadata<X>,
      coin_y_metadata: &CoinMetadata<Y>,        
      ctx: &mut TxContext
    ): Coin<LPCoin<Stable, X, Y>> {
      // Calculate the scalar of the decimals.
      let decimals_x = math::pow(10, coin::get_decimals(coin_x_metadata));
      let decimals_y = math::pow(10, coin::get_decimals(coin_y_metadata));

      create_pool<Stable, X, Y>(storage, clock_object, coin_x, coin_y, decimals_x, decimals_y, true, ctx)
    }


    /**
    * @dev This fn allows the caller to deposit coins X and Y on the Pool<X, Y>.
    * This function will not throw if one of the coins has a value of 0, but the caller will get shares (LPCoin) with a value of 0.
    * @param storage the object that stores the pools object_bag 
    * @param clock_object The Clock shared object at @0x6
    * @param coin_x The Coin<X> the user wishes to deposit on Pool<X, Y>
    * @param coin_y The Coin<Y> the user wishes to deposit on Pool<X, Y>
    * @param vlp_coin_min_amount the minimum amount of shares to receive. It prevents high slippage from frontrunning. 
    * @return LPCoin with a value in proportion to the Coin deposited and the reserves of the Pool<X, Y>.
    * Requirements: 
    * - Coins X and Y must be sorted.
    */
    public fun add_liquidity<C, X, Y>(   
      storage: &mut DEXStorage,
      clock_object: &Clock,
      coin_x: Coin<X>,
      coin_y: Coin<Y>,
      vlp_coin_min_amount: u64,
      ctx: &mut TxContext
      ): Coin<LPCoin<C, X, Y>> {
        assert!(is_curve<C>(), ERROR_WRONG_CURVE);

        // Save the value of the coins locally.
        let coin_x_value = coin::value(&coin_x);
        let coin_y_value = coin::value(&coin_y);
        
        // Save the fee_to address because storage will be moved to `borrow_mut_pool`
        let fee_to = storage.fee_to;
        // Borrow the Pool<X, Y>. It is mutable.
        // It will throw if X and Y are not sorted.
        let pool = borrow_mut_pool<C, X, Y>(storage);
        // Not allowed to perform this action during a flash loan
        assert!(!pool.locked, ERROR_POOL_IS_LOCKED);

        // Mint the fee amount if `fee_to` is not the @0x0. 
        // The fee amount is equivalent to 1/5 of all commissions collected. 
        // If the fee is on, we need to save the K in the k_last key to calculate the next fee amount. 
        let is_fee_on = mint_fee(pool, fee_to, ctx);

        // Make sure that both coins havea value greater than 0 to save gas for the user.
        assert!(coin_x_value != 0 && coin_y_value != 0, ERROR_ADD_LIQUIDITY_ZERO_AMOUNT);

        // Save the reserves and supply amount of Pool<X, Y> locally.
        let (coin_x_reserve, coin_y_reserve, supply) = get_amounts(pool);

        // Calculate an optimal coinX and coinY amount to keep the pool's ratio
        let (optimal_x_amount, optimal_y_amount) = calculate_optimal_add_liquidity(
          coin_x_value,
          coin_y_value,
          coin_x_reserve,
          coin_y_reserve
        );
    
        // Repay the extra amount
        if (coin_x_value > optimal_x_amount) pay::split_and_transfer(&mut coin_x, coin_x_value - optimal_x_amount, tx_context::sender(ctx), ctx);
        if (coin_y_value > optimal_y_amount) pay::split_and_transfer(&mut coin_y, coin_y_value - optimal_y_amount, tx_context::sender(ctx), ctx);

        // Calculate the number of shares to mint. Note if of the coins has a value of 0. The `shares_to_mint` will be 0.
        let share_to_mint = math::min(
          mul_div(coin_x_value, supply, coin_x_reserve),
          mul_div(coin_y_value, supply, coin_y_reserve)
        );

        // Make sure the user receives the minimum amount desired or higher.
        assert!(share_to_mint >= vlp_coin_min_amount, ERROR_SLIPPAGE);

        // Deposit the coins in the Pool<X, Y>.
        let new_reserve_x = balance::join(&mut pool.balance_x, coin::into_balance(coin_x));
        let new_reserve_y = balance::join(&mut pool.balance_y, coin::into_balance(coin_y));

        // Emit the AddLiquidity event
        event::emit(
          AddLiquidity<Pool<C, X, Y>> {
          id: object:: uid_to_inner(&pool.id), 
          sender: tx_context::sender(ctx), 
          coin_x_amount: coin_x_value, 
          coin_y_amount: coin_y_value,
          shares_minted: share_to_mint
          }
        );

        // If the fee mechanism is turned on, we need to save the K for the next calculation.
        if (is_fee_on) pool.k_last = k<C>(new_reserve_x, new_reserve_y, pool.decimals_x, pool.decimals_y);

        let coin = coin::from_balance(balance::increase_supply(&mut pool.lp_coin_supply, share_to_mint), ctx);

        // Update TWAP
        sync_obervations(pool, clock_object);

        // Return the shares(LPCoin) to the caller.
        coin
      }

    /**
    * @dev It allows the caller to redeem his underlying coins in proportions to the LPCoins he burns. 
    * @param storage the object that stores the pools object_bag 
    * @param clock_object The shared Clock object 0x6
    * @param lp_coin the shares to burn
    * @param coin_x_min_amount the minimum value of Coin<X> the caller wishes to receive.
    * @param coin_y_min_amount the minimum value of Coin<Y> the caller wishes to receive.
    * @return A tuple with Coin<X> and Coin<Y>.
    * Requirements: 
    * - Coins X and Y must be sorted.
    */
    public fun remove_liquidity<C, X, Y>(   
      storage: &mut DEXStorage,
      clock_object: &Clock,
      lp_coin: Coin<LPCoin<C, X, Y>>,
      coin_x_min_amount: u64,
      coin_y_min_amount: u64,
      ctx: &mut TxContext
      ): (Coin<X>, Coin<Y>) {
        assert!(is_curve<C>(), ERROR_WRONG_CURVE);
        // Store the value of the shares locally
        let lp_coin_value = coin::value(&lp_coin);

        // Throw if the lp_coin has a value of 0 to save gas.
        assert!(lp_coin_value != 0, ERROR_REMOVE_LIQUIDITY_ZERO_AMOUNT);

        // Save the fee_to address because storage will be moved to `borrow_mut_pool`
        let fee_to = storage.fee_to;
        // Borrow the Pool<X, Y>. It is mutable.
        // It will throw if X and Y are not sorted.
        let pool = borrow_mut_pool<C, X, Y>(storage);
        // Not allowed to perform this action during a flash loan
        assert!(!pool.locked, ERROR_POOL_IS_LOCKED);

        // Mint the fee amount if `fee_to` is not the @0x0. 
        // The fee amount is equivalent to 1/5 of all commissions collected. 
        // If the fee is on, we need to save the K in the k_last key to calculate the next fee amount. 
        let is_fee_on = mint_fee(pool, fee_to, ctx);

        // Save the reserves and supply amount of Pool<X, Y> locally.
        let (coin_x_reserve, coin_y_reserve, lp_coin_supply) = get_amounts(pool);

        // Calculate the amount of coins to receive in proportion of the `lp_coin_value`. 
        // It maintains the current K of the pool.
        let coin_x_removed = mul_div(lp_coin_value, coin_x_reserve, lp_coin_supply);
        let coin_y_removed = mul_div(lp_coin_value, coin_y_reserve, lp_coin_supply);
        
        // Make sure that the caller receives the minimum amount desired.
        assert!(coin_x_removed >= coin_x_min_amount, ERROR_REMOVE_LIQUIDITY_X_AMOUNT);
        assert!(coin_y_removed >= coin_y_min_amount, ERROR_REMOVE_LIQUIDITY_Y_AMOUNT);

        // Burn the LPCoin deposited
        balance::decrease_supply(&mut pool.lp_coin_supply, coin::into_balance(lp_coin));

        // Emit the RemoveLiquidity event
        event::emit(
          RemoveLiquidity<Pool<C, X, Y>> {
          id: object:: uid_to_inner(&pool.id), 
          sender: tx_context::sender(ctx), 
          coin_x_out: coin_x_removed,
          coin_y_out: coin_y_removed,
          shares_destroyed: lp_coin_value
          }
        );

        // Store the current K for the next fee calculation.
        if (is_fee_on) pool.k_last = k<C>(coin_x_reserve - coin_x_removed, coin_y_reserve - coin_y_removed, pool.decimals_x, pool.decimals_y);

        let coin_x = coin::take(&mut pool.balance_x, coin_x_removed, ctx);
        let coin_y = coin::take(&mut pool.balance_y, coin_y_removed, ctx);

        // Update the TWAP
        sync_obervations(pool, clock_object);

        // Remove the coins from the Pool<X, Y> and return to the caller.
        (
          coin_x,
          coin_y,
        )
      }

    /**
    * @dev It returns an immutable Pool<X, Y>. 
    * @param storage the object that stores the pools object_bag 
    * @return The pool for Coins X and Y.
    * Requirements: 
    * - Coins X and Y must be sorted.
    */
    public fun borrow_pool<C, X, Y>(storage: &DEXStorage): &Pool<C, X, Y> {
     object_bag::borrow<String, Pool<C, X, Y>>(&storage.pools, utils::get_coin_info_string<LPCoin<C, X, Y>>())
    }

    /**
    * @dev It indicates to the caller if Pool<X, Y> has been deployed. 
    * @param storage the object that stores the pools object_bag 
    * @return bool True if the pool has been deployed.
    * Requirements: 
    * - Coins X and Y must be sorted.
    */
    public fun is_pool_deployed<C, X, Y>(storage: &DEXStorage): bool {
      object_bag::contains(&storage.pools, utils::get_coin_info_string<LPCoin<C, X, Y>>())
    }

    /**
    * @dev It returns the ID of a pool
    * @return pool ID
    * Requirements: 
    * - Coins X and Y must be sorted.
    */
    public fun get_pool_id<C, X, Y>(storage: &DEXStorage): ID {
      let pool = borrow_pool<C, X, Y>(storage);
      object::id(pool)
    }

    /**
    * @param pool an immutable Pool<X, Y>
    * @return It returns a triple of Tuple<coin_x_reserves, coin_y_reserves, lp_coin_supply>. 
    */
    public fun get_amounts<C, X, Y>(pool: &Pool<C, X, Y>): (u64, u64, u64) {
        (
            balance::value(&pool.balance_x),
            balance::value(&pool.balance_y),
            balance::supply_value(&pool.lp_coin_supply)
        )
    }

    /**
    * @dev A helper fn to calculate the value of tokenA in tokenB in a Pool<A, B>. This function remove the commission of 0.3% from the `coin_in_amount`.
    * @param coin_in_amount The amount being sold
    * @param balance_in The reserves of the coin being sold in a Pool<A, B>. 
    * @param balance_out The reserves of the coin being bought in a Pool<A, B>. 
    * @return the value of A in terms of B.
    */
    public fun calculate_v_value_out(coin_in_amount: u64, balance_in: u64, balance_out: u64): u64 {

        let (coin_in_amount, balance_in, balance_out) = (
          (coin_in_amount as u256),
          (balance_in as u256),
          (balance_out as u256)
        );

        // We calculate the amount being sold after the fee. 
        let token_in_amount_minus_fees_adjusted = coin_in_amount - ((coin_in_amount * VOLATILE_FEE_PERCENT) / PRECISION);

        // We maintain the K invariant = reserveB * amountA / reserveA + amount A
        let numerator = balance_out * token_in_amount_minus_fees_adjusted;
        let denominator = balance_in + token_in_amount_minus_fees_adjusted; 

        // Divide and convert the value back to u64 and return.
        ((numerator / denominator) as u64) 
    }   

        /**
    * @dev A helper fn to calculate the value of tokenA in tokenB in a Pool<A, B>. This function remove the commission of 0.05% from the `coin_in_amount`.
    * Algo logic taken from Andre Cronje's Solidly
    * @param coin_amount the amount being sold
    * @param balance_x the reserves of the Coin<X> in a Pool<A, B>. 
    * @param balance_y The reserves of the Coin<Y> in a Pool<A, B>. 
    * @param is_x it indicates if the `coin_amount` is Coin<X> or Coin<Y>.
    * @return the value of A in terms of B.
    */
  public fun calculate_s_value_out<C, X, Y>(
      pool: &Pool<C, X, Y>,
      coin_amount: u64,
      balance_x: u64,
      balance_y:u64,
      is_x: bool
    ): u64 {
      assert!(!is_volatile<C>(), ERROR_WRONG_CURVE);
        let _k = k<Stable>(balance_x, balance_y, pool.decimals_x, pool.decimals_y);  

        // Precision is used to scale the number for more precise calculations. 
        // We convert them to u256 for more precise calculations and to avoid overflows.
        let (coin_amount, balance_x, balance_y) =
         (
          (coin_amount as u256),
          (balance_x as u256),
          (balance_y as u256)
         );

        // We calculate the amount being sold after the fee. 
     // We calculate the amount being sold after the fee. 
        let token_in_amount_minus_fees_adjusted = coin_amount - ((coin_amount * STABLE_FEE_PERCENT) / PRECISION);

        let decimals_x = (pool.decimals_x as u256);
        let decimals_y = (pool.decimals_y as u256);

        // Calculate the stable curve invariant k = x3y+y3x 
        // We need to consider stable coins with different decimal values
        let reserve_x = (balance_x * PRECISION) / decimals_x;
        let reserve_y = (balance_y * PRECISION) / decimals_y;

        let amount_in = token_in_amount_minus_fees_adjusted * PRECISION 
          / if (is_x) { decimals_x } else {decimals_y };


        let y = if (is_x) 
          { reserve_y - y(amount_in + reserve_x, _k, reserve_y) } 
          else 
          { reserve_x - y(amount_in + reserve_y, _k, reserve_x) };

        ((y * if (is_x) { decimals_y } else { decimals_x }) / PRECISION as u64)   
    }             
          

   /**
   * @dev It sells the Coin<X> in a Pool<X, Y> for Coin<Y>. 
   * @param storage the object that stores the pools object_bag 
   * @param clock_object The shared Clock object 0x6
   * @param coin_x Coin<X> being sold. 
   * @param coin_y_min_value the minimum value of Coin<Y> the caller will accept.
   * @return Coin<Y> bought.
   * Requirements: 
   * - Coins X and Y must be sorted.
   */ 
   public fun swap_token_x<C, X, Y>(
      storage: &mut DEXStorage, 
      clock_object: &Clock,
      coin_x: Coin<X>,
      coin_y_min_value: u64,
      ctx: &mut TxContext
      ): Coin<Y> {
        assert!(is_curve<C>(), ERROR_WRONG_CURVE);
        // Ensure we are selling something
        assert!(coin::value(&coin_x) != 0, ERROR_ZERO_VALUE_SWAP);

        // Borrow a mutable Pool<X, Y>.
        let pool = borrow_mut_pool<C, X, Y>(storage);
        // Not allowed to perform this action during a flash loan
        assert!(!pool.locked, ERROR_POOL_IS_LOCKED);

        // Conver the coin being sold in balance.
        let coin_x_balance = coin::into_balance(coin_x);

        // Save the reserves of Pool<X, Y> locally.
        let (coin_x_reserve, coin_y_reserve, _) = get_amounts(pool);  

        let prev_k = k<C>(coin_x_reserve, coin_y_reserve, pool.decimals_x, pool.decimals_y);

        // Store the value being sold locally
        let coin_x_value = balance::value(&coin_x_balance);
        
        // Calculte how much value of Coin<Y> the caller will receive.
        let coin_y_value = if (is_volatile<C>()) {
          calculate_v_value_out(coin_x_value, coin_x_reserve, coin_y_reserve)
        } else {
          calculate_s_value_out(pool, coin_x_value, coin_x_reserve, coin_y_reserve, true)
        };

        // Make sure the caller receives more than the minimum amount. 
        assert!(coin_y_value >=  coin_y_min_value, ERROR_SLIPPAGE);

        // Emit the SwapTokenX event
        event::emit(
          SwapTokenX<C, X, Y> {
            id: object:: uid_to_inner(&pool.id), 
            sender: tx_context::sender(ctx),
            coin_x_in: coin_x_value, 
            coin_y_out: coin_y_value 
            }
          );

        // Add Balance<X> to the Pool<X, Y> 
        balance::join(&mut pool.balance_x, coin_x_balance);
        // Remove the value being bought and give to the caller in Coin<Y>.
       let coin = coin::take(&mut pool.balance_y, coin_y_value, ctx);

       sync_obervations(pool, clock_object);

       let (coin_x_reserve, coin_y_reserve, _) = get_amounts(pool);  
       assert!(k<C>(coin_x_reserve, coin_y_reserve, pool.decimals_x, pool.decimals_y) > prev_k, ERROR_INVALID_K); 
       
       coin
      }

  /**
   * @dev It sells the Coin<Y> in a Pool<X, Y> for Coin<X>. 
   * @param storage the object that stores the pools object_bag 
   * @param clock_object The shared Clock object 0x6
   * @param coin_y Coin<Y> being sold. 
   * @param coin_x_min_value the minimum value of Coin<X> the caller will accept.
   * @return Coin<X> bought.
   * Requirements: 
   * - Coins X and Y must be sorted.
   */ 
    public fun swap_token_y<C, X, Y>(
      storage: &mut DEXStorage, 
      clock_object: &Clock,
      coin_y: Coin<Y>,
      coin_x_min_value: u64,
      ctx: &mut TxContext
      ): Coin<X> {
        assert!(is_curve<C>(), ERROR_WRONG_CURVE);
        // Ensure we are selling something
        assert!(coin::value(&coin_y) != 0, ERROR_ZERO_VALUE_SWAP);
        

        // Borrow a mutable Pool<X, Y>.
        let pool = borrow_mut_pool<C, X, Y>(storage);
        // Not allowed to perform this action during a flash loan
        assert!(!pool.locked, ERROR_POOL_IS_LOCKED);

        // Convert the coin being sold in balance.
        let coin_y_balance = coin::into_balance(coin_y);

        // Save the reserves of Pool<X, Y> locally.
        let (coin_x_reserve, coin_y_reserve, _) = get_amounts(pool);  

        let prev_k = k<C>(coin_x_reserve, coin_y_reserve, pool.decimals_x, pool.decimals_y);

        // Store the value being sold locally
        let coin_y_value = balance::value(&coin_y_balance);

        // Calculte how much value of Coin<X> the caller will receive.
        let coin_x_value = if (is_volatile<C>()) {
          calculate_v_value_out(coin_y_value, coin_y_reserve, coin_x_reserve)
        } else {
          calculate_s_value_out(pool, coin_y_value, coin_x_reserve, coin_y_reserve, false)
        };

        assert!(coin_x_value >=  coin_x_min_value, ERROR_SLIPPAGE);

        // Emit the SwapTokenY event
        event::emit(
          SwapTokenY<C, X, Y> {
            id: object:: uid_to_inner(&pool.id), 
            sender: tx_context::sender(ctx),
            coin_y_in: coin_y_value, 
            coin_x_out: coin_x_value 
            }
          );

        // Add Balance<Y> to the Pool<X, Y> 
        balance::join(&mut pool.balance_y, coin_y_balance);
        // Remove the value being bought and give to the caller in Coin<X>.
        let coin = coin::take(&mut pool.balance_x, coin_x_value, ctx);

        // Update the TWAP
        sync_obervations(pool, clock_object);

        let (coin_x_reserve, coin_y_reserve, _) = get_amounts(pool);  
        assert!(k<C>(coin_x_reserve, coin_y_reserve, pool.decimals_x, pool.decimals_y) > prev_k, ERROR_INVALID_K);

        coin
      }

  /**
   * @dev It lends Coin<X> and Coin<Y> to the caller from VPool<X, Y>. 
   * @param storage the object that stores the pools object_bag 
   * @param amount_x The amount of Coin<X> the caller wishes to borrow
   * @param amount_y The amount of Coin<Y> the caller wishes to borrow
   * @return Receipt<X, Y>, Coin<X>, Coin<Y>
   * Requirements: 
   * - The caller must call the fn repay_flash_loan before the execution ends
   */ 
    public fun flash_loan<C, X, Y>(
      storage: &mut DEXStorage,
      amount_x: u64,
      amount_y: u64,
      ctx: &mut TxContext
      ): (Receipt<C, X, Y>, Coin<X>, Coin<Y>) {
        assert!(is_curve<C>(), ERROR_WRONG_CURVE);
        // Borrow a mutable Pool<X, Y>.
        let pool = borrow_mut_pool<C, X, Y>(storage);
        // Not allowed to perform this action during a flash loan
        assert!(!pool.locked, ERROR_POOL_IS_LOCKED);

        // lock the pool to prevent reetrancies
        pool.locked = true;

        // Read the values before taking the coins
        let (coin_x_reserve, coin_y_reserve, _) = get_amounts(pool);

        let prev_k = k<C>(coin_x_reserve, coin_y_reserve, pool.decimals_x, pool.decimals_y);

        // The pool must have enough liquidity to lend
        assert!(balance::value(&pool.balance_x) >= amount_x && balance::value(&pool.balance_y) >= amount_y, ERROR_NOT_ENOUGH_LIQUIDITY_TO_LEND);

        // Remove the coins from the pool
        let coin_x = coin::take(&mut pool.balance_x, amount_x, ctx);
        let coin_y = coin::take(&mut pool.balance_y, amount_y, ctx);

        // Store the repay amounts in a Receipt struct
        let receipt = Receipt<C, X, Y> { 
          pool_id: object::id(pool),  
          repay_amount_x: amount_x + ((((amount_x as u256) * FLASH_LOAN_FEE_PERCENT) / PRECISION) as u64),
          repay_amount_y: amount_y + ((((amount_y as u256) * FLASH_LOAN_FEE_PERCENT) / PRECISION) as u64),
          prev_k
        };

        // Give the coins and receipt to the caller
        (receipt, coin_x, coin_y)
    }

  /**
   * @dev It allows the caller to repay his flash loan. 
   * @param storage the object that stores the pools object_bag 
   * @param clock_object The shared Clock object 0x6
   * @param receipt The Receipt struct created by the flash loan
   * @param coin_x The Coin<X> to be repaid to VPool<X, Y>
   * @param coin_y The Coin<Y> to be repaid to VPool<X, Y>
   * Requirements: 
   * - The value of Coin<X> and Coin<Y> must be equal or higher than the receipt repay amount_x and amount_y
   */ 
    public fun repay_flash_loan<C, X, Y>(
      storage: &mut DEXStorage,
      clock_object: &Clock,
      receipt: Receipt<C, X, Y>,
      coin_x: Coin<X>,
      coin_y: Coin<Y>
    ) {
      assert!(is_curve<C>(), ERROR_WRONG_CURVE);
      // Borrow a mutable Pool<X, Y>.
      let pool = borrow_mut_pool<C, X, Y>(storage);  
      // Take the data from Receipt
      let Receipt { pool_id, repay_amount_x, repay_amount_y, prev_k } = receipt;

      // Ensure that the correct pool and amounts are being repaid
   
      assert!(object::id(pool) == pool_id, ERROR_WRONG_POOL);
      assert!(coin::value(&coin_x) >= repay_amount_x, ERROR_WRONG_REPAY_AMOUNT_X);
      assert!(coin::value(&coin_y) >= repay_amount_y, ERROR_WRONG_REPAY_AMOUNT_Y);

      // Deposit the coins in the pool
      coin::put(&mut pool.balance_x, coin_x);
      coin::put(&mut pool.balance_y, coin_y);

      // Read values after depositing the coins
      let (coin_x_reserve, coin_y_reserve, _) = get_amounts(pool);

      assert!(k<C>(coin_x_reserve, coin_y_reserve, pool.decimals_x, pool.decimals_y) > prev_k, ERROR_INVALID_K);
      // Unlock the pool
      pool.locked = false;

      // Update TWAP
      sync_obervations(pool, clock_object);
    }

    /**
    * @dev It returns the flash loan fee percentage along with the precision
    * @return fee, precision
    */
    public fun get_flash_loan_fee_percent(): (u256, u256) {
      (FLASH_LOAN_FEE_PERCENT, PRECISION)
    }

    /**
    * @dev It returns the data inside a receipt
    * @param receipt The Receipt<X, Y> generated by the function flash_loan
    * @return (pool_id, repay_amount_x, repay_amount_y, prev_k)
    */
    public fun get_receipt_data<C, X, Y>(receipt: &Receipt<C, X, Y>): (ID, u64, u64, u256) {
      (receipt.pool_id, receipt.repay_amount_x, receipt.repay_amount_y, receipt.prev_k)
    }  

    /**
    * @dev It contains the inner logic to create pools
    * @param storage the object that stores the pools object_bag
    * @param clock_object The shared Clock object 0x6
    * @oaram coin_x the first token of the pool
    * @param coin_y the scond token of the pool
    * @param decimals_x The decimals factor of Coin<X> - if a coin has 9 decimals this is 1e9
    * @param decimals_y The decimals factor of Coin<Y> - if a coin has 9 decimals this is 1e9
    * @param is_stable it indicates if a pool is stable of volatile
    * @return The number of shares as LPCoins that can be used later on to redeem his coins + commissions.
    */
    fun create_pool<C, X, Y>(
      storage: &mut DEXStorage,
      clock_object: &Clock,
      coin_x: Coin<X>,
      coin_y: Coin<Y>,
      decimals_x: u64,
      decimals_y: u64,
      is_stable: bool,
      ctx: &mut TxContext
    ): Coin<LPCoin<C, X, Y>> {
      // Store the value of the coins locally
      let coin_x_value = coin::value(&coin_x);
      let coin_y_value = coin::value(&coin_y);

      // Ensure that the both coins have a value greater than 0.
      assert!(coin_x_value != 0 && coin_y_value != 0, ERROR_CREATE_PAIR_ZERO_VALUE);
      assert!(utils::are_coins_sorted<X, Y>(), ERROR_UNSORTED_COINS);

      // Construct the name of the LPCoin, which will be used as a key to store the pool data.
      // This fn will throw if X and Y are not sorted.
      let type = utils::get_coin_info_string<LPCoin<C, X, Y>>();

      // Checks that the pool does not exist.
      assert!(!object_bag::contains(&storage.pools, type), ERROR_POOL_EXISTS);

      // Calculate the number of shares
      // We square root it twice because LPCoins do not have decimals and we do not want the supply to be very large
      let shares = (sqrt_u256(sqrt_u256(((coin_x_value as u256) * (coin_y_value as u256)))) as u64);

      // Create the LP coin for the Pool<X, Y>. 
      // This coin has 0 decimals and no metadata 
      let supply = balance::create_supply(LPCoin<C, X, Y> {});
      // The number of shares the zero address will receive to prevent 0 divisions in the future.
      let min_liquidity_balance = balance::increase_supply(&mut supply, MINIMUM_LIQUIDITY);
      // The number of shares (LPCoins<X, Y>) the caller will receive.
      let sender_balance = balance::increase_supply(&mut supply, shares);

      // Transfer the zero address shares
      transfer::public_transfer(coin::from_balance(min_liquidity_balance, ctx), @0x0);

      // Calculate an id for the pool and the event
      let pool_id = object::new(ctx);

      event::emit(
          PoolCreated<Pool<Volatile, X, Y>> {
            id: object::uid_to_inner(&pool_id),
            shares: shares,
            value_x: coin_x_value,
            value_y: coin_y_value,
            sender: tx_context::sender(ctx)
          }
        );

      let current_timestamp = clock::timestamp_ms(clock_object);

      // Store the new pool in Storage.pools
      object_bag::add(
        &mut storage.pools,
        type,
        Pool {
          id: pool_id,
          k_last: k<C>(coin_x_value, coin_y_value, decimals_x, decimals_y),
          lp_coin_supply: supply,
          balance_x: coin::into_balance<X>(coin_x),
          balance_y: coin::into_balance<Y>(coin_y),
          decimals_x,
          decimals_y,
          is_stable,
          observations: init_observation_vector(),
          timestamp_last: current_timestamp,
          balance_x_cumulative_last: utils::calculate_cumulative_balance((coin_x_value as u256), current_timestamp, 0),
          balance_y_cumulative_last: utils::calculate_cumulative_balance((coin_y_value as u256), current_timestamp, 0),
          locked: false
        }
      );

      // Return the caller shares
      coin::from_balance(sender_balance, ctx)
    }

    /**
    * @dev It returns the AMM constant invariant based on {C}. If {C} is {Volatile}, it returns k = x * y
    * @param x The reserves of Coin<X> in Pool<X, Y>
    * @parma y the reserves of Coin<Y> in Pool<X, Y>
    * @param decimals_x the decimal factor of Coin<X>. So for Sui which has 9 decimals it would be 1e9
    * @param decimals_y the decimal factor of Coin<Y>.
    * @return The {Volatile} or {Stable} K
    */
    fun k<C>(
      x: u64, 
      y: u64,
      decimals_x: u64,
      decimals_y: u64
    ): u256 {
      if (is_volatile<C>()) {
        (x as u256) * (y as u256)
      } else {
        let (x, y, decimals_x, decimals_y) =
        (
          (x as u256),
          (y as u256),
          (decimals_x as u256),
          (decimals_y as u256)
        );  

      let _x = (x * PRECISION) / decimals_x;
      let _y = (y * PRECISION) / decimals_y;
      let _a = (_x * _y) / PRECISION;
      let _b = ((_x * _x) / PRECISION + (_y * _y) / PRECISION);
      (_a * _b) / PRECISION // k = x^3y + y^3x
      }
    }  

    /**
    * @notice It is based on https://github.com/curvefi/curve-contract/blob/master/contracts/pools/aeth/StableSwapAETH.vy
    * @dev Calculates the reserves of out the out token based on reserves of token in (x0), current k and reserves of token out. 
    * @param x0 The reserves of the tokenIn + amountIn - fee
    * @param xy The current K of the pool
    * @param y The reserves of the token that is being bought
    */
    fun y(x0: u256, xy: u256, y: u256): u256 {
      let i = 0;

      // Here it is using the Newton's method to to make sure that y and and y_prev are equal   
      while (i < 255) {
        i = i + 1;
        let y_prev = y;
        let k = f(x0, y);
        
        if (k < xy) {
          let dy = (((xy - k) * PRECISION) / d(x0, y)) + 1; // round up
            y = y + dy;
          } else {
            y = y - ((k - xy) * PRECISION) / d(x0, y);
          };

        if (y > y_prev) {
            if (y - y_prev <= 1) break
          } else {
            if (y_prev - y <= 1) break
          };
      };
      y
    }

    fun f(x0: u256, y: u256): u256 {
        (x0 * ((((y * y) / PRECISION) * y) / PRECISION)) /
            PRECISION +
            (((((x0 * x0) / PRECISION) * x0) / PRECISION) * y) /
            PRECISION
    }

    fun d(x0: u256, y: u256): u256 {
      (3 * x0 * ((y * y) / PRECISION)) /
            PRECISION +
            ((((x0 * x0) / PRECISION) * x0) / PRECISION)
    }

  /**
  * @dev A utility function to ensure that the user is adding the correct amounts of Coin<X> and Coin<Y> to a Pool<X, Y>
  * @param desired_amount_x The value of Coin<X> the user wishes to add
  * @param desired_amount_y The value of Coin<Y> the user wishes to add
  * @param reserve_x The current Balance<X> in the pool
  * @param reserve_y The current Balance<Y> in the pool
  * @ return (u64, u64) (coin_x_amount_to_add, coin_y_amount_to_add)
  */
  fun calculate_optimal_add_liquidity(
    desired_amount_x: u64,
    desired_amount_y: u64,
    reserve_x: u64,
    reserve_y: u64
  ): (u64, u64) {

    if (reserve_x == 0 && reserve_y == 0) return (desired_amount_x, desired_amount_y);

    let optimal_y_amount = utils::quote_liquidity(desired_amount_x, reserve_x, reserve_y);
    if (desired_amount_y >= optimal_y_amount) return (desired_amount_x, optimal_y_amount);

    let optimal_x_amount = utils::quote_liquidity(desired_amount_y, reserve_y, reserve_x);
    (optimal_x_amount, desired_amount_y)
  }

    /**
    * @dev It returns a mutable Pool<X, Y>. 
    * @param storage the object that stores the pools object_bag 
    * @return The pool for Coins X and Y.
    * Requirements: 
    * - Coins X and Y must be sorted.
    */
    fun borrow_mut_pool<C, X, Y>(storage: &mut DEXStorage): &mut Pool<C, X, Y> {
       object_bag::borrow_mut<String, Pool<C, X, Y>>(&mut storage.pools, utils::get_coin_info_string<LPCoin<C, X, Y>>())
      }   

    /**
    * @dev It mints a commission to the `fee_to` address. It collects 20% of the commissions.
    * We collect the fee by minting more shares.
    * @param pool mutable Pool<X, Y>
    * @param fee_to the address that will receive the fee. 
    * @return bool it indicates if a fee was collected or not.
    * Requirements: 
    * - Coins X and Y must be sorted.
    */
      fun mint_fee<C, X, Y>(pool: &mut Pool<C, X, Y>, fee_to: address, ctx: &mut TxContext): bool {
          // If the `fee_to` is the zero address @0x0, we do not collect any protocol fees.
          let is_fee_on = fee_to != @0x0;

          if (is_fee_on) {
            // We need to know the last K to calculate how many fees were collected
            if (pool.k_last != 0) {
              // Find the sqrt of the current K
              let root_k = sqrt_u256(k<C>(balance::value(&pool.balance_x), balance::value(&pool.balance_y), pool.decimals_x, pool.decimals_y));
              // Find the sqrt of the previous K
              let root_k_last = sqrt_u256(pool.k_last);

              // If the current K is higher, trading fees were collected. It is the only way to increase the K. 
              if (root_k > root_k_last) {
                // Number of fees collected in shares
                let numerator = (balance::supply_value(&pool.lp_coin_supply) as u256) * (root_k - root_k_last);
                // logic to collect 1/5
                let denominator = (root_k * 5) + root_k_last;
                let liquidity = numerator / denominator;
                if (liquidity != 0) {
                  // Increase the shares supply and transfer to the `fee_to` address.
                  let new_balance = balance::increase_supply(&mut pool.lp_coin_supply, (liquidity as u64));
                  let new_coins = coin::from_balance(new_balance, ctx);
                  transfer::public_transfer(new_coins, fee_to);
                }
              }
            };
          // If the protocol fees are off and we have k_last value, we remove it.  
          } else if (pool.k_last != 0) {
            pool.k_last = 0;
          };

       is_fee_on
    }

    /**
     * @dev It finds the current index of a timestamp in the observations vector. 
     * @param timestamp Any u64 timestamp
     * @return firstObservation the first observation of the current epoch considering the TWAP is up to date.
     */
    fun observation_index_of(timestamp: u64): u64 {
      (timestamp / PERIOD_SIZE) % GRANULARITY
    }

    /**
    * @dev It finds the first observation in the observations vector based on the window and period size
    * @param observations The observations vector of the pool
    * @param current_timestamp The current timestamp in the shared Clock object 
    * @return The index of the first observation in the observations vector
    */
    fun get_first_observation_index(current_timestamp: u64): u64 {
      let index = observation_index_of(current_timestamp);

      (index + 1) % GRANULARITY
    }

    /**
    * @dev It updates the observations based on the latest balance changes
    * @param pool The pool that we will be updating the observations
    * @param clock_object The shared object with id @0x6
    */
    fun sync_obervations<C, X, Y>(pool: &mut Pool<C, X, Y>, clock_object: &Clock) {
      let current_timestamp = clock::timestamp_ms(clock_object);

      let time_elapsed = current_timestamp - pool.timestamp_last;

      if (time_elapsed == 0) return;

      pool.timestamp_last = current_timestamp;

      let balance_x = balance::value(&pool.balance_x);
      let balance_y = balance::value(&pool.balance_y);

      let balance_x_cumulative = utils::calculate_cumulative_balance((balance_x as u256), current_timestamp, pool.balance_x_cumulative_last);
      let balance_y_cumulative = utils::calculate_cumulative_balance((balance_y as u256), current_timestamp, pool.balance_y_cumulative_last);

      pool.balance_x_cumulative_last = balance_x_cumulative;
      pool.balance_y_cumulative_last = balance_y_cumulative;

      let index = observation_index_of(current_timestamp);

      let observation = vector::borrow_mut(&mut pool.observations, index);

      let time_elapsed = current_timestamp - observation.timestamp;

      if (time_elapsed > PERIOD_SIZE) {
         observation.timestamp = current_timestamp;
         observation.balance_x_cumulative = balance_x_cumulative;
         observation.balance_y_cumulative = balance_y_cumulative;
      }
    }

    /**
    * @dev It returns the price of a Coin based on a Pool's TWAP Oracle
    * @param storage The shared Storage object of this module
    * @param clock_object The shared Clock object with id @0x6 
    * @param coin_x_value The price will be returned in terms of how much coin_x_value in Coin<X>  returns when swapping to Coin<Y>
    * @retuen the value in Coin<Y>
    */
    public fun get_coin_x_price<C, X, Y>(storage: &mut DEXStorage, clock_object: &Clock, coin_x_value: u64): u64 {
      assert!(is_curve<C>(), ERROR_WRONG_CURVE);

      let pool = borrow_mut_pool<C, X, Y>(storage);
      // Not allowed to perform this action during a flash loan
      assert!(!pool.locked, ERROR_POOL_IS_LOCKED);

      let current_timestamp = clock::timestamp_ms(clock_object);

      let first_observation_index = get_first_observation_index(current_timestamp);

      let first_observation = vector::borrow(&pool.observations, first_observation_index);

      let time_elapsed = current_timestamp - first_observation.timestamp;

      assert!(WINDOW > time_elapsed, ERROR_MISSING_OBSERVATION);

      let first_observation_balance_x_cumulative = first_observation.balance_x_cumulative;
      let first_observation_balance_y_cumulative = first_observation.balance_y_cumulative;

      sync_obervations(pool, clock_object);

      let cumulative_x = if (first_observation_balance_x_cumulative > pool.balance_x_cumulative_last) {
        let rem = utils::max_u_128() - first_observation_balance_x_cumulative;
        pool.balance_x_cumulative_last + rem
      } else {
        pool.balance_x_cumulative_last - first_observation_balance_x_cumulative
      };

      let cumulative_y = if (first_observation_balance_y_cumulative > pool.balance_y_cumulative_last) {
        let rem = utils::max_u_128() - first_observation_balance_y_cumulative;
        pool.balance_y_cumulative_last + rem
      } else {
        pool.balance_y_cumulative_last - first_observation_balance_y_cumulative
      };

      let coin_x_reserve = (cumulative_x / (time_elapsed as u256) as u64);
      let coin_y_reserve = (cumulative_y / (time_elapsed as u256) as u64);

      // Calculte how much value of Coin<Y> the caller will receive.
      if (is_volatile<C>()) {
          calculate_v_value_out(coin_x_value, coin_x_reserve, coin_y_reserve)
        } else {
          calculate_s_value_out(pool, coin_x_value, coin_x_reserve, coin_y_reserve, true)
        }
    }

    /**
    * @dev It returns the price of a Coin based on a Pool's TWAP Oracle
    * @param storage The shared Storage object of this module
    * @param clock_object The shared Clock object with id @0x6 
    * @param coin_y_value The price will be returned in terms of how much coin_y_value in Coin<Y>  returns when swapping to Coin<X>
    * @retuen the value in Coin<Y>
    */
    public fun get_coin_y_price<C, X, Y>(storage: &mut DEXStorage, clock_object: &Clock, coin_y_value: u64): u64 {
      assert!(is_curve<C>(), ERROR_WRONG_CURVE);

      let pool = borrow_mut_pool<C, X, Y>(storage);
      // Not allowed to perform this action during a flash loan
      assert!(!pool.locked, ERROR_POOL_IS_LOCKED);

      let current_timestamp = clock::timestamp_ms(clock_object);

      let first_observation_index = get_first_observation_index(current_timestamp);

      let first_observation = vector::borrow(&pool.observations, first_observation_index);

      let time_elapsed = current_timestamp - first_observation.timestamp;

      assert!(WINDOW > time_elapsed, ERROR_MISSING_OBSERVATION);

      let first_observation_balance_x_cumulative = first_observation.balance_x_cumulative;
      let first_observation_balance_y_cumulative = first_observation.balance_y_cumulative;

      sync_obervations(pool, clock_object);

      let cumulative_x = if (first_observation_balance_x_cumulative > pool.balance_x_cumulative_last) {
        let rem = utils::max_u_128() - first_observation_balance_x_cumulative;
        pool.balance_x_cumulative_last + rem
      } else {
        pool.balance_x_cumulative_last - first_observation_balance_x_cumulative
      };

      let cumulative_y = if (first_observation_balance_y_cumulative > pool.balance_y_cumulative_last) {
        let rem = utils::max_u_128() - first_observation_balance_y_cumulative;
        pool.balance_y_cumulative_last + rem
      } else {
        pool.balance_y_cumulative_last - first_observation_balance_y_cumulative
      };

      let coin_x_reserve = (cumulative_x / (time_elapsed as u256) as u64);
      let coin_y_reserve = (cumulative_y / (time_elapsed as u256) as u64);

      // Calculte how much value of Coin<X> the caller will receive.
      if (is_volatile<C>()) {
        calculate_v_value_out(coin_y_value, coin_y_reserve, coin_x_reserve)
      } else {
        calculate_s_value_out(pool, coin_y_value, coin_x_reserve, coin_y_reserve, false)
      }
    }

    /**
    * @dev It returns a vector with 5 empty observations 
    * @return vector<Observation>
    */
    fun init_observation_vector(): vector<Observation> {
      let result = vector::empty<Observation>();

      vector::push_back(&mut result, Observation {
        timestamp: 0,
        balance_x_cumulative: 0,
        balance_y_cumulative: 0
      });

      vector::push_back(&mut result, Observation {
        timestamp: 0,
        balance_x_cumulative: 0,
        balance_y_cumulative: 0
      });

      vector::push_back(&mut result, Observation {
        timestamp: 0,
        balance_x_cumulative: 0,
        balance_y_cumulative: 0
      });
      
      vector::push_back(&mut result, Observation {
        timestamp: 0,
        balance_x_cumulative: 0,
        balance_y_cumulative: 0
      });

      vector::push_back(&mut result, Observation {
        timestamp: 0,
        balance_x_cumulative: 0,
        balance_y_cumulative: 0
      });
      
      result
    }

    /**
    * @dev Admin only fn to update the fee_to. 
    * @param _ the DEXAdminCap 
    * @param storage the object that stores the pools object_bag 
    * @param new_fee_to the new `fee_to`.
    */
    entry public fun update_fee_to(
      _:&DEXAdminCap, 
      storage: &mut DEXStorage,
      new_fee_to: address
       ) {
      storage.fee_to = new_fee_to;
      event::emit(NewFeeTo { fee_to: new_fee_to });
    }

    /**
    * @dev Admin only fn to transfer the ownership. 
    * @param admin_cap the DEXAdminCap 
    * @param new_admin the new admin.
    */
    entry public fun transfer_admin_cap(
      admin_cap: DEXAdminCap,
      new_admin: address
    ) {
      assert!(new_admin != @0x0, ERROR_NO_ZERO_ADDRESS);
      transfer::transfer(admin_cap, new_admin);
      event::emit(NewAdmin { admin: new_admin });
    }

    /**
    * @dev A utility function to return the values balance_x, balance_y and lp_coin_supply of a pool
    * @param storage The DEXStorage shared object
    * return (u64, u64, u64) (balance_x, balance_y, lp_coin_supply)
    */
    public fun get_pool_info<C, X, Y>(storage: &DEXStorage): (u64, u64, u64){
      assert!(is_curve<C>(), ERROR_WRONG_CURVE);
      let pool = borrow_pool<C, X, Y>(storage);
      (balance::value(&pool.balance_x), balance::value(&pool.balance_y), balance::supply_value(&pool.lp_coin_supply))
    }

    /**
    * @dev A utility function to read the (pool.balance_x_cumulative_last, pool.balance_y_cumulative_last) from Pool<C, X, Y>
    * @param storage The DEXStorage shared object
    * return (u256, u256) (pool.balance_x_cumulative_last, pool.balance_y_cumulative_last)   
    */
    public fun get_pool_cumulative_balances_last<C, X, Y>(storage: &DEXStorage): (u256, u256) {
      assert!(is_curve<C>(), ERROR_WRONG_CURVE);
      let pool = borrow_pool<C, X, Y>(storage);
      (pool.balance_x_cumulative_last, pool.balance_y_cumulative_last)
    }

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(ctx);
    }
    
    #[test_only]
    public fun get_observations<C, X, Y>(storage: &DEXStorage): &vector<Observation> {
      let pool = borrow_pool<C, X, Y>(storage);
      &pool.observations
    }

    #[test_only]
    public fun get_period_size(): u64 {
      PERIOD_SIZE
    }

    #[test_only]
    public fun get_granularity(): u64 {
      GRANULARITY
    }

    #[test_only]
    public fun get_fee_to(storage: &DEXStorage): address {
      storage.fee_to
    }

    #[test_only]
    public fun get_k_last<C, X, Y>(storage: &DEXStorage): u256 {
      assert!(is_curve<C>(), ERROR_WRONG_CURVE);
      let pool = borrow_pool<C, X, Y>(storage);
      pool.k_last
    }

    #[test_only]
    public fun get_pool_metadata<C, X, Y>(storage: &DEXStorage): (u64, u64) {
      let pool = borrow_pool<C, X, Y>(storage);
      (pool.decimals_x, pool.decimals_y)
    }

    #[test_only]
    public fun is_pool_locked<C, X, Y>(storage: &DEXStorage): bool {
      let pool = borrow_pool<C, X, Y>(storage);
      pool.locked
    }

    #[test_only]
    public fun get_minimum_liquidity(): u64 {
      MINIMUM_LIQUIDITY
    }

    #[test_only]
    public fun get_k<C>(
      x: u64, 
      y: u64,
      decimals_x: u64,
      decimals_y: u64
    ): u256 {
      k<C>(x, y, decimals_x, decimals_y)
    }
}
