module interest_protocol::dex_volatile {
  use std::ascii::{String}; 

  use sui::tx_context::{Self, TxContext};
  use sui::coin::{Self, Coin};
  use sui::balance::{Self, Supply, Balance};
  use sui::object::{Self,UID, ID};
  use sui::transfer;
  use sui::math;
  use sui::object_bag::{Self, ObjectBag};
  use sui::event;

  use interest_protocol::utils;
  use interest_protocol::math::{mul_div, sqrt_u256};

  const MINIMUM_LIQUIDITY: u64 = 10;
  const PRECISION: u256 = 1000000000000000000; //1e18;
  const FEE_PERCENT: u256 = 3000000000000000; //0.3%
  const FLASH_LOAN_FEE_PERCENT: u256 = 5000000000000000; //0.5% 

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

    struct VolatileDEXAdminCap has key {
      id: UID,
    }

    struct Storage has key {
      id: UID,
      pools: ObjectBag,
      fee_to: address
    }

    struct VLPCoin<phantom X, phantom Y> has drop {}

    struct VPool<phantom X, phantom Y> has key, store {
        id: UID,
        k_last: u256,
        lp_coin_supply: Supply<VLPCoin<X, Y>>,
        balance_x: Balance<X>,
        balance_y: Balance<Y>
    }

    // Important this struct cannot have any type abilities
    struct Receipt<phantom X, phantom Y> {
      pool_id: ID,
      repay_amount_x: u64,
      repay_amount_y: u64
    }

    // Events
    struct PoolCreated<phantom P> has copy, drop {
      id: ID,
      shares: u64,
      value_x: u64,
      value_y: u64,
      sender: address
    }

    struct SwapTokenX<phantom X, phantom Y> has copy, drop {
      id: ID,
      sender: address,
      coin_x_in: u64,
      coin_y_out: u64
    }

    struct SwapTokenY<phantom X, phantom Y> has copy, drop {
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

    /**
    * @dev It gives the caller the VolatileDEXAdminCap object. The VolatileDEXAdminCap allows the holder to update the fee_to key. 
    * It shares the Storage object with the Sui Network.
    */
    fun init(ctx: &mut TxContext) {
      // Give administrator capabilities to the deployer
      // He has the ability to update the fee_to key on the Storage
      transfer::transfer(
        VolatileDEXAdminCap { 
          id: object::new(ctx)
        }, 
        tx_context::sender(ctx)
        );

      // Share the Storage object
      transfer::share_object(
         Storage {
           id: object::new(ctx),
           pools: object_bag::new(ctx),
           fee_to: @dev
         }
      );
    }

    /**
    * @notice The zero address receives a small amount of shares to prevent zero divisions in the future. 
    * @notice Please make sure that the tokens X and Y are sorted before calling this fn.
    * @dev It creates a new Pool with X and Y coins. The pool accepts swaps using the k = x * y invariant.
    * @param storage the object that stores the pools object_bag
    * @oaram coin_x the first token of the pool
    * @param coin_y the scond token of the pool
    * @return The number of shares as VLPCoins that can be used later on to redeem his coins + commissions.
    * Requirements: 
    * - It will throw if the X and Y are not sorted.
    * - Both coins must have a value greater than 0. 
    * - The pool has a maximum capacity to prevent overflows.
    * - There can only be one pool per each token pair, regardless of their order.
    */
    public fun create_pool<X, Y>(
      storage: &mut Storage,
      coin_x: Coin<X>,
      coin_y: Coin<Y>,
      ctx: &mut TxContext
    ): Coin<VLPCoin<X, Y>> {
      // Store the value of the coins locally
      let coin_x_value = coin::value(&coin_x);
      let coin_y_value = coin::value(&coin_y);

      // Ensure that the both coins have a value greater than 0.
      assert!(coin_x_value != 0 && coin_y_value != 0, ERROR_CREATE_PAIR_ZERO_VALUE);
      assert!(utils::are_coins_sorted<X, Y>(), ERROR_UNSORTED_COINS);

      // Construct the name of the VLPCoin, which will be used as a key to store the pool data.
      // This fn will throw if X and Y are not sorted.
      let type = utils::get_coin_info_string<VLPCoin<X, Y>>();

      // Checks that the pool does not exist.
      assert!(!object_bag::contains(&storage.pools, type), ERROR_POOL_EXISTS);

      // Calculate the constant product k = x * y
      let _k = k(coin_x_value, coin_y_value) - (MINIMUM_LIQUIDITY as u256);
      let shares = (sqrt_u256(_k) as u64);

      // Create the VLP coin for the Pool<X, Y>. 
      // This coin has 0 decimals and no metadata 
      let supply = balance::create_supply(VLPCoin<X, Y> {});
      // The number of shares the zero address will receive to prevent 0 divisions in the future.
      let min_liquidity_balance = balance::increase_supply(&mut supply, MINIMUM_LIQUIDITY);
      // The number of shares (VLPCoins<X, Y>) the caller will receive.
      let sender_balance = balance::increase_supply(&mut supply, shares);

      // Transfer the zero address shares
      transfer::transfer(coin::from_balance(min_liquidity_balance, ctx), @0x0);

      // Calculate an id for the pool and the event
      let pool_id = object::new(ctx);

      event::emit(
          PoolCreated<VPool<X, Y>> {
            id: object::uid_to_inner(&pool_id),
            shares: shares,
            value_x: coin_x_value,
            value_y: coin_y_value,
            sender: tx_context::sender(ctx)
          }
        );

      // Store the new pool in Storage.pools
      object_bag::add(
        &mut storage.pools,
        type,
        VPool {
          id: pool_id,
          k_last: _k,
          lp_coin_supply: supply,
          balance_x: coin::into_balance<X>(coin_x),
          balance_y: coin::into_balance<Y>(coin_y)
          }
      );

      // Return the caller shares
      coin::from_balance(sender_balance, ctx)
    }


    /**
    * @dev This fn allows the caller to deposit coins X and Y on the Pool<X, Y>.
    * This function will not throw if one of the coins has a value of 0, but the caller will get shares (VLPCoin) with a value of 0.
    * @param storage the object that stores the pools object_bag 
    * @param coin_x The Coin<X> the user wishes to deposit on Pool<X, Y>
    * @param coin_y The Coin<Y> the user wishes to deposit on Pool<X, Y>
    * @param vlp_coin_min_amount the minimum amount of shares to receive. It prevents high slippage from frontrunning. 
    * @return VLPCoin with a value in proportion to the Coin deposited and the reserves of the Pool<X, Y>.
    * Requirements: 
    * - Coins X and Y must be sorted.
    */
    public fun add_liquidity<X, Y>(   
      storage: &mut Storage,
      coin_x: Coin<X>,
      coin_y: Coin<Y>,
      vlp_coin_min_amount: u64,
      ctx: &mut TxContext
      ): Coin<VLPCoin<X, Y>> {
        // Save the value of the coins locally.
        let coin_x_value = coin::value(&coin_x);
        let coin_y_value = coin::value(&coin_y);
        
        // Save the fee_to address because storage will be moved to `borrow_mut_pool`
        let fee_to = storage.fee_to;
        // Borrow the Pool<X, Y>. It is mutable.
        // It will throw if X and Y are not sorted.
        let pool = borrow_mut_pool<X, Y>(storage);

        // Mint the fee amount if `fee_to` is not the @0x0. 
        // The fee amount is equivalent to 1/5 of all commissions collected. 
        // If the fee is on, we need to save the K in the k_last key to calculate the next fee amount. 
        let is_fee_on = mint_fee(pool, fee_to, ctx);

        // Make sure that both coins havea value greater than 0 to save gas for the user.
        assert!(coin_x_value != 0 && coin_y_value != 0, ERROR_ADD_LIQUIDITY_ZERO_AMOUNT);

        // Save the reserves and supply amount of Pool<X, Y> locally.
        let (coin_x_reserve, coin_y_reserve, supply) = get_amounts(pool);

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
          AddLiquidity<VPool<X, Y>> {
          id: object:: uid_to_inner(&pool.id), 
          sender: tx_context::sender(ctx), 
          coin_x_amount: coin_x_value, 
          coin_y_amount: coin_y_value,
          shares_minted: share_to_mint
          }
        );

        // If the fee mechanism is turned on, we need to save the K for the next calculation.
        if (is_fee_on) pool.k_last = k(new_reserve_x, new_reserve_y);

        // Return the shares(VLPCoin) to the caller.
        coin::from_balance(balance::increase_supply(&mut pool.lp_coin_supply, share_to_mint), ctx)
      }

    /**
    * @dev It allows the caller to redeem his underlying coins in proportions to the VLPCoins he burns. 
    * @param storage the object that stores the pools object_bag 
    * @param lp_coin the shares to burn
    * @param coin_x_min_amount the minimum value of Coin<X> the caller wishes to receive.
    * @param coin_y_min_amount the minimum value of Coin<Y> the caller wishes to receive.
    * @return A tuple with Coin<X> and Coin<Y>.
    * Requirements: 
    * - Coins X and Y must be sorted.
    */
    public fun remove_liquidity<X, Y>(   
      storage: &mut Storage,
      lp_coin: Coin<VLPCoin<X, Y>>,
      coin_x_min_amount: u64,
      coin_y_min_amount: u64,
      ctx: &mut TxContext
      ): (Coin<X>, Coin<Y>) {
        // Store the value of the shares locally
        let lp_coin_value = coin::value(&lp_coin);

        // Throw if the lp_coin has a value of 0 to save gas.
        assert!(lp_coin_value != 0, ERROR_REMOVE_LIQUIDITY_ZERO_AMOUNT);

        // Save the fee_to address because storage will be moved to `borrow_mut_pool`
        let fee_to = storage.fee_to;
        // Borrow the Pool<X, Y>. It is mutable.
        // It will throw if X and Y are not sorted.
        let pool = borrow_mut_pool<X, Y>(storage);

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

        // Burn the VLPCoin deposited
        balance::decrease_supply(&mut pool.lp_coin_supply, coin::into_balance(lp_coin));

        // Emit the RemoveLiquidity event
        event::emit(
          RemoveLiquidity<VPool<X, Y>> {
          id: object:: uid_to_inner(&pool.id), 
          sender: tx_context::sender(ctx), 
          coin_x_out: coin_x_removed,
          coin_y_out: coin_y_removed,
          shares_destroyed: lp_coin_value
          }
        );

        // Store the current K for the next fee calculation.
        if (is_fee_on) pool.k_last = k(coin_x_reserve - coin_x_removed, coin_y_reserve - coin_y_removed);

        // Remove the coins from the Pool<X, Y> and return to the caller.
        (
          coin::take(&mut pool.balance_x, coin_x_removed, ctx),
          coin::take(&mut pool.balance_y, coin_y_removed, ctx),
        )
      }

    /**
    * @dev It returns an immutable Pool<X, Y>. 
    * @param storage the object that stores the pools object_bag 
    * @return The pool for Coins X and Y.
    * Requirements: 
    * - Coins X and Y must be sorted.
    */
    public fun borrow_pool<X, Y>(storage: &Storage): &VPool<X, Y> {
      object_bag::borrow<String, VPool<X, Y>>(&storage.pools, utils::get_coin_info_string<VLPCoin<X, Y>>())
    }

    /**
    * @dev It indicates to the caller if Pool<X, Y> has been deployed. 
    * @param storage the object that stores the pools object_bag 
    * @return bool True if the pool has been deployed.
    * Requirements: 
    * - Coins X and Y must be sorted.
    */
    public fun is_pool_deployed<X, Y>(storage: &Storage):bool {
      object_bag::contains(&storage.pools, utils::get_coin_info_string<VLPCoin<X, Y>>())
    }

    /**
    * @dev It returns the ID of a pool
    * @return pool ID
    * Requirements: 
    * - Coins X and Y must be sorted.
    */
    public fun get_pool_id<X, Y>(storage: &Storage): ID {
      let pool = borrow_pool<X, Y>(storage);
      object::id(pool)
    }

    /**
    * @param pool an immutable Pool<X, Y>
    * @return It returns a triple of Tuple<coin_x_reserves, coin_y_reserves, lp_coin_supply>. 
    */
    public fun get_amounts<X, Y>(pool: &VPool<X, Y>): (u64, u64, u64) {
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
    public fun calculate_value_out(coin_in_amount: u64, balance_in: u64, balance_out: u64): u64 {

        let (coin_in_amount, balance_in, balance_out) = (
          (coin_in_amount as u256),
          (balance_in as u256),
          (balance_out as u256)
        );

        // We calculate the amount being sold after the fee. 
        let token_in_amount_minus_fees_adjusted = coin_in_amount - ((coin_in_amount * FEE_PERCENT) / PRECISION);

        // We maintain the K invariant = reserveB * amountA / reserveA + amount A
        let numerator = balance_out * token_in_amount_minus_fees_adjusted;
        let denominator = balance_in + token_in_amount_minus_fees_adjusted; 

        // Divide and convert the value back to u64 and return.
        ((numerator / denominator) as u64) 
    }             

   /**
   * @dev It sells the Coin<X> in a Pool<X, Y> for Coin<Y>. 
   * @param storage the object that stores the pools object_bag 
   * @param coin_x Coin<X> being sold. 
   * @param coin_y_min_value the minimum value of Coin<Y> the caller will accept.
   * @return Coin<Y> bought.
   * Requirements: 
   * - Coins X and Y must be sorted.
   */ 
   public fun swap_token_x<X, Y>(
      storage: &mut Storage, 
      coin_x: Coin<X>,
      coin_y_min_value: u64,
      ctx: &mut TxContext
      ): Coin<Y> {
        // Ensure we are selling something
        assert!(coin::value(&coin_x) != 0, ERROR_ZERO_VALUE_SWAP);

        // Borrow a mutable Pool<X, Y>.
        let pool = borrow_mut_pool<X, Y>(storage);

        // Conver the coin being sold in balance.
        let coin_x_balance = coin::into_balance(coin_x);

        // Save the reserves of Pool<X, Y> locally.
        let (coin_x_reserve, coin_y_reserve, _) = get_amounts(pool);  

        // Store the value being sold locally
        let coin_x_value = balance::value(&coin_x_balance);
        
        // Calculte how much value of Coin<Y> the caller will receive.
        let coin_y_value = calculate_value_out(coin_x_value, coin_x_reserve, coin_y_reserve);

        // Make sure the caller receives more than the minimum amount. 
        assert!(coin_y_value >=  coin_y_min_value, ERROR_SLIPPAGE);

        // Emit the SwapTokenX event
        event::emit(
          SwapTokenX<X, Y> {
            id: object:: uid_to_inner(&pool.id), 
            sender: tx_context::sender(ctx),
            coin_x_in: coin_x_value, 
            coin_y_out: coin_y_value 
            }
          );

        // Add Balance<X> to the Pool<X, Y> 
        balance::join(&mut pool.balance_x, coin_x_balance);
        // Remove the value being bought and give to the caller in Coin<Y>.
        coin::take(&mut pool.balance_y, coin_y_value, ctx)
      }

  /**
   * @dev It sells the Coin<Y> in a Pool<X, Y> for Coin<X>. 
   * @param storage the object that stores the pools object_bag 
   * @param coin_y Coin<Y> being sold. 
   * @param coin_x_min_value the minimum value of Coin<X> the caller will accept.
   * @return Coin<X> bought.
   * Requirements: 
   * - Coins X and Y must be sorted.
   */ 
    public fun swap_token_y<X, Y>(
      storage: &mut Storage, 
      coin_y: Coin<Y>,
      coin_x_min_value: u64,
      ctx: &mut TxContext
      ): Coin<X> {
        // Ensure we are selling something
        assert!(coin::value(&coin_y) != 0, ERROR_ZERO_VALUE_SWAP);

        // Borrow a mutable Pool<X, Y>.
        let pool = borrow_mut_pool<X, Y>(storage);

        // Convert the coin being sold in balance.
        let coin_y_balance = coin::into_balance(coin_y);

        // Save the reserves of Pool<X, Y> locally.
        let (coin_x_reserve, coin_y_reserve, _) = get_amounts(pool);  

        // Store the value being sold locally
        let coin_y_value = balance::value(&coin_y_balance);

        // Calculte how much value of Coin<X> the caller will receive.
        let coin_x_value = calculate_value_out(coin_y_value, coin_y_reserve, coin_x_reserve);

        assert!(coin_x_value >=  coin_x_min_value, ERROR_SLIPPAGE);

        // Emit the SwapTokenY event
        event::emit(
          SwapTokenY<X, Y> {
            id: object:: uid_to_inner(&pool.id), 
            sender: tx_context::sender(ctx),
            coin_y_in: coin_y_value, 
            coin_x_out: coin_x_value 
            }
          );

        // Add Balance<Y> to the Pool<X, Y> 
        balance::join(&mut pool.balance_y, coin_y_balance);
        // Remove the value being bought and give to the caller in Coin<X>.
        coin::take(&mut pool.balance_x, coin_x_value, ctx)
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
    public fun flash_loan<X, Y>(
      storage: &mut Storage,
      amount_x: u64,
      amount_y: u64,
      ctx: &mut TxContext
      ): (Receipt<X, Y>, Coin<X>, Coin<Y>) {
        // Borrow a mutable Pool<X, Y>.
        let pool = borrow_mut_pool<X, Y>(storage);

        // The pool must have enough liquidity to lend
        assert!(balance::value(&pool.balance_x) >= amount_x && balance::value(&pool.balance_y) >= amount_y, ERROR_NOT_ENOUGH_LIQUIDITY_TO_LEND);

        // Remove the coins from the pool
        let coin_x = coin::take(&mut pool.balance_x, amount_x, ctx);
        let coin_y = coin::take(&mut pool.balance_y, amount_y, ctx);

        // Store the repay amounts in a Receipt struct
        let receipt = Receipt<X, Y> { 
          pool_id: object::id(pool),  
          repay_amount_x: amount_x + ((((amount_x as u256) * FLASH_LOAN_FEE_PERCENT) / PRECISION) as u64),
          repay_amount_y: amount_y + ((((amount_y as u256) * FLASH_LOAN_FEE_PERCENT) / PRECISION) as u64),
        };

        // Give the coins and receipt to the caller
        (receipt, coin_x, coin_y)
    }

  /**
   * @dev It allows the caller to repay his flash loan. 
   * @param storage the object that stores the pools object_bag 
   * @param receipt The Receipt struct created by the flash loan
   * @param coin_x The Coin<X> to be repaid to VPool<X, Y>
   * @param coin_y The Coin<Y> to be repaid to VPool<X, Y>
   * Requirements: 
   * - The value of Coin<X> and Coin<Y> must be equal or higher than the receipt repay amount_x and amount_y
   */ 
    public fun repay_flash_loan<X, Y>(
      storage: &mut Storage,
      receipt: Receipt<X, Y>,
      coin_x: Coin<X>,
      coin_y: Coin<Y>
    ) {
      // Borrow a mutable Pool<X, Y>.
      let pool = borrow_mut_pool<X, Y>(storage);  
      // Take the data from Receipt
      let Receipt { pool_id, repay_amount_x, repay_amount_y } = receipt;

      // Ensure that the correct pool and amounts are being repaid
      assert!(object::id(pool) == pool_id, ERROR_WRONG_POOL);
      assert!(coin::value(&coin_x) >= repay_amount_x, ERROR_WRONG_REPAY_AMOUNT_X);
      assert!(coin::value(&coin_y) >= repay_amount_y, ERROR_WRONG_REPAY_AMOUNT_Y);

      // Deposit the coins in the pool
      coin::put(&mut pool.balance_x, coin_x);
      coin::put(&mut pool.balance_y, coin_y);
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
    */
    public fun get_receipt_data<X, Y>(receipt: &Receipt<X, Y>): (ID, u64, u64) {
      (receipt.pool_id, receipt.repay_amount_x, receipt.repay_amount_y)
    }  

    fun k(x: u64, y: u64): u256 {
      (x as u256) * (y as u256)
    }  

    /**
    * @dev It returns a mutable Pool<X, Y>. 
    * @param storage the object that stores the pools object_bag 
    * @return The pool for Coins X and Y.
    * Requirements: 
    * - Coins X and Y must be sorted.
    */
    fun borrow_mut_pool<X, Y>(storage: &mut Storage): &mut VPool<X, Y> {
        object_bag::borrow_mut<String, VPool<X, Y>>(&mut storage.pools, utils::get_coin_info_string<VLPCoin<X, Y>>())
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
      fun mint_fee<X, Y>(pool: &mut VPool<X, Y>, fee_to: address, ctx: &mut TxContext): bool {
          // If the `fee_to` is the zero address @0x0, we do not collect any protocol fees.
          let is_fee_on = fee_to != @0x0;

          if (is_fee_on) {
            // We need to know the last K to calculate how many fees were collected
            if (pool.k_last != 0) {
              // Find the sqrt of the current K
              let root_k = sqrt_u256(k(balance::value(&pool.balance_x), balance::value(&pool.balance_y)));
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
                  transfer::transfer(new_coins, fee_to);
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
    * @dev Admin only fn to update the fee_to. 
    * @param _ the VolatileDEXAdminCap 
    * @param storage the object that stores the pools object_bag 
    * @param new_fee_to the new `fee_to`.
    */
    entry public fun update_fee_to(
      _:&VolatileDEXAdminCap, 
      storage: &mut Storage,
      new_fee_to: address
       ) {
      storage.fee_to = new_fee_to;
    }

    /**
    * @dev Admin only fn to transfer the ownership. 
    * @param admin_cap the VolatileDEXAdminCap 
    * @param new_admin the new admin.
    */
    entry public fun transfer_admin_cap(
      admin_cap: VolatileDEXAdminCap,
      new_admin: address
    ) {
      transfer::transfer(admin_cap, new_admin);
    }

    public fun get_pool_info<X, Y>(storage: &Storage): (u64, u64, u64){
      let pool = borrow_pool<X, Y>(storage);
      (balance::value(&pool.balance_x), balance::value(&pool.balance_y), balance::supply_value(&pool.lp_coin_supply))
    }

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(ctx);
    }

    #[test_only]
    public fun get_fee_to(storage: &Storage,): address {
      storage.fee_to
    }

    #[test_only]
    public fun get_k_last<X, Y>(storage: &mut Storage): u256 {
      let pool = borrow_mut_pool<X, Y>(storage);
      pool.k_last
    }
}
