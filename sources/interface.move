module interest_protocol::interface {
  use std::vector;

  use sui::coin::{Coin, CoinMetadata};
  use sui::tx_context::{Self, TxContext};
  use sui::transfer;
  use sui::clock::{Self, Clock};
  use sui::object::{ID};

  use interest_protocol::dex::{Self, Storage as Storage, LPCoin};
  use interest_protocol::master_chef::{Self, MasterChefStorage, AccountStorage};
  use interest_protocol::ipx::{Self, IPXStorage, IPX};
  use interest_protocol::utils::{destroy_zero_or_transfer, are_coins_sorted};
  use interest_protocol::router;

  const ERROR_TX_DEADLINE_REACHED: u64 = 1;

  /**
  * @dev This function does not require the coins to be sorted. It will send back any unused value. 
  * It create a volatile Pool with Coins X and Y
  * @param storage The storage object of the interest_protocol::dex 
  * @param clock_object The shared Clock object at id @0x6
  * @param coin_x  Coin<X> 
  * @param coin_y Coin<Y> 
  */
  entry public fun create_v_pool<X, Y>(
      storage: &mut Storage,
      clock_object: &Clock,
      coin_x: Coin<X>,
      coin_y: Coin<Y>,
      ctx: &mut TxContext
  ) {

    // Sorts for the caller - to make it easier for the frontend
    if (are_coins_sorted<X, Y>()) {
      transfer::public_transfer(
        dex::create_v_pool(
          storage,
          clock_object,
          coin_x,
          coin_y,
          ctx
        ),
        tx_context::sender(ctx)
      )
    } else {
      transfer::public_transfer(
        dex::create_v_pool(
          storage,
          clock_object,
          coin_y,
          coin_x,
          ctx
        ),
        tx_context::sender(ctx)
      )
    }
  }

    /**
  * @dev This function does not require the coins to be sorted. It will send back any unused value. 
  * It create a volatile Pool with Coins X and Y
  * @param storage The storage object of the interest_protocol::dex
  * @param clock_object The shared Clock object at id @0x6
  * @param coin_x  Coin<X> 
  * @param coin_y A  Coin<Y> 
  * @param coin_x_metadata The CoinMetadata object of Coin<X>
  * @param coin_y_metadata The CoinMetadata object of Coin<Y>
  */
  entry public fun create_s_pool<X, Y>(
      storage: &mut Storage,
      clock_object: &Clock,
      coin_x: Coin<X>,
      coin_y: Coin<Y>,
      coin_x_metadata: &CoinMetadata<X>,
      coin_y_metadata: &CoinMetadata<Y>,
      ctx: &mut TxContext
  ) {

    // Sorts for the caller - to make it easier for the frontend
    if (are_coins_sorted<X, Y>()) {
      transfer::public_transfer(
        dex::create_s_pool(
          storage,
          clock_object,
          coin_x,
          coin_y,
          coin_x_metadata,
          coin_y_metadata,
          ctx
        ),
        tx_context::sender(ctx)
      )
    } else {
      transfer::public_transfer(
        dex::create_s_pool(
          storage,
          clock_object,
          coin_y,
          coin_x,
          coin_y_metadata,
          coin_x_metadata,
          ctx
        ),
        tx_context::sender(ctx)
      )
    }
  }

  /**
  * @dev This function does not require the coins to be sorted. It will send back any unused value. 
  * It performs a swap and finds the most profitable pool. X -> Y or Y -> X on Pool<X, Y>
  * @param storage The storage object of the interest_protocol::dex 
  * @param clock_object The shared Clock object
  * @param vector_x Coin<X> 
  * @param vector_y Coin<Y> 
  * @param coin_out_min_value The minimum value the caller expects to receive to protect agaisnt slippage
  * @param deadline Timestamp indicating the deadline for this TX to be submitted
  */
  entry public fun swap<X, Y>(
    storage: &mut Storage,
    clock_object: &Clock,
    coin_x: Coin<X>,
    coin_y: Coin<Y>,
    coin_out_min_value: u64,
    deadline: u64,
    ctx: &mut TxContext
  ) {
    assert!(deadline >= clock::timestamp_ms(clock_object), ERROR_TX_DEADLINE_REACHED);

  if (are_coins_sorted<X, Y>()) {
   let (coin_x, coin_y) = router::swap<X, Y>(
      storage,
      clock_object,
      coin_x,
      coin_y,
      coin_out_min_value,
      ctx
    );

    destroy_zero_or_transfer(coin_x, ctx);
    destroy_zero_or_transfer(coin_y, ctx);
    } else {
    let (coin_y, coin_x) = router::swap<Y, X>(
      storage,
      clock_object,
      coin_y,
      coin_x,
      coin_out_min_value,
      ctx
    );
    
    destroy_zero_or_transfer(coin_x, ctx);
    destroy_zero_or_transfer(coin_y, ctx);
    }
  }

  /**
  * @dev This function does not require the coins to be sorted. It will send back any unused value. 
  * It performs an one hop swap and finds the most profitable pool. X -> Z -> Y or Y -> Z -> X on Pool<X, Z> -> Pool<Z, Y>
  * @param storage The storage object of the interest_protocol::dex
  * @param clock_object The shared Clock object
  * @param coin_x  Coin<X> 
  * @param coin_y Coin<Y> 
  * @param coin_out_min_value The minimum value the caller expects to receive to protect agaisnt slippage
  * @param deadline Timestamp indicating the deadline for this TX to be submitted
  */
  entry public fun one_hop_swap<X, Y, Z>(
    storage: &mut Storage,
    clock_object: &Clock,
    coin_x: Coin<X>,
    coin_y: Coin<Y>,
    coin_out_min_value: u64,
    deadline: u64,
    ctx: &mut TxContext
  ) {
    assert!(deadline >= clock::timestamp_ms(clock_object), ERROR_TX_DEADLINE_REACHED);

    let (coin_x, coin_y) = router::one_hop_swap<X, Y, Z>(
      storage,
      clock_object,
      coin_x,
      coin_y,
      coin_out_min_value,
      ctx
    );

    destroy_zero_or_transfer(coin_x, ctx);
    destroy_zero_or_transfer(coin_y, ctx);
  }

  /**
  * @dev This function does not require the coins to be sorted. It will send back any unused value. 
  * It performs a three hop swap and finds the most profitable pool. X -> B1 -> B2 -> Y or Y -> B1 -> B2 -> X on Pool<X, Z> -> Pool<B1, B2> -> Pool<B2, Y>
  * @param storage The storage object of the interest_protocol::dex  
  * @param clock_object The shared Clock object
  * @param coin_x Coin<X> 
  * @param coin_y Coin<Y> 
  * @param coin_out_min_value The minimum value the caller expects to receive to protect agaisnt slippage
  * @param deadline Timestamp indicating the deadline for this TX to be submitted
  */
  entry public fun two_hop_swap<X, Y, B1, B2>(
    storage: &mut Storage,
    clock_object: &Clock,
    coin_x: Coin<X>,
    coin_y: Coin<Y>,
    coin_out_min_value: u64,
    deadline: u64,
    ctx: &mut TxContext
  ) {
    assert!(deadline >= clock::timestamp_ms(clock_object), ERROR_TX_DEADLINE_REACHED);

    let (coin_x, coin_y) = router::two_hop_swap<X, Y, B1, B2>(
      storage,
      clock_object,
      coin_x,
      coin_y,
      coin_out_min_value,
      ctx
    );

    destroy_zero_or_transfer(coin_x, ctx);
    destroy_zero_or_transfer(coin_y, ctx);
  }

  /**
  * @dev This function does not require the coins to be sorted. It will send back any unused value. 
  * It adds liquidity to a Pool
  * @param storage The storage object of the interest_protocol::dex  
  * @param clock_object The shared Clock object
  * @param coin_x Coin<X> 
  * @param coin_y Coin<Y> 
  * @param coin_out_min_value The minimum value the caller expects to receive to protect agaisnt slippage
  */
  entry public fun add_liquidity<C, X, Y>(
    storage: &mut Storage,
    clock_object: &Clock,
    coin_x: Coin<X>,
    coin_y: Coin<Y>,
    coin_min_amount: u64,
    ctx: &mut TxContext
  ) {

      if (are_coins_sorted<X, Y>()) {
        transfer::public_transfer(
          router::add_liquidity<C, X, Y>(
          storage,
          clock_object,
          coin_x,
          coin_y,
          coin_min_amount,
          ctx
          ),
        tx_context::sender(ctx)
      )  
      } else {
        transfer::public_transfer(
          router::add_liquidity<C, Y, X>(
          storage,
          clock_object,
          coin_y,
          coin_x,
          coin_min_amount,
          ctx
          ),
        tx_context::sender(ctx)
      )  
      }
    }

  /**
  * @dev This function REQUIRES the coins to be sorted. It will send back any unused value. 
  * It removes liquidity from a volatile pool based on the shares
  * @param storage The storage object of the interest_protocol::dex 
  * @param clock_object The shared Clock object
  * @param vector_lp_coin A vector of several VLPCoins
  * @param coin_amount_in The value the caller wishes to deposit for VLPCoins 
  * @param coin_x_min_amount The minimum amount of Coin<X> the user wishes to receive
  * @param coin_y_min_amount The minimum amount of Coin<Y> the user wishes to receive
  */
  entry public fun remove_liquidity<C, X, Y>(
    storage: &mut Storage,
    clock_object: &Clock,
    lp_coin: Coin<LPCoin<C, X, Y>>,
    coin_x_min_amount: u64,
    coin_y_min_amount: u64,
    ctx: &mut TxContext
  ){
    let sender = tx_context::sender(ctx);

    let (coin_x, coin_y) = dex::remove_liquidity(
      storage,
      clock_object,
      lp_coin, 
      coin_x_min_amount,
      coin_y_min_amount,
      ctx
    );

    transfer::public_transfer(coin_x, sender);
    transfer::public_transfer(coin_y, sender);
  }

/**
* @notice It allows a user to deposit a Coin<T> in a farm to earn Coin<IPX>. 
* @param storage The MasterChefStorage shared object
* @param accounts_storage The AccountStorage shared object
* @param ipx_storage The shared Object of IPX
* @param clock_object The Clock object created at genesis
* @param coin Coin<T>
*/
  entry public fun stake<T>(
    storage: &mut MasterChefStorage,
    accounts_storage: &mut AccountStorage,
    ipx_storage: &mut IPXStorage,
    clock_object: &Clock,
    token: Coin<T>,
    ctx: &mut TxContext
  ) {

    // Stake and send Coin<IPX> rewards to the caller.
    transfer::public_transfer(
      master_chef::stake(
        storage,
        accounts_storage,
        ipx_storage,
        clock_object,
        token,
        ctx
      ),
      tx_context::sender(ctx)
    );
  }

/**
* @notice It allows a user to withdraw an amount of Coin<T> from a farm. 
* @param storage The MasterChefStorage shared object
* @param accounts_storage The AccountStorage shared object
* @param ipx_storage The shared Object of IPX
* @param clock_object The Clock object created at genesis
* @param coin_value The amount of Coin<T> the caller wishes to withdraw
*/
  entry public fun unstake<T>(
    storage: &mut MasterChefStorage,
    accounts_storage: &mut AccountStorage,
    ipx_storage: &mut IPXStorage,
    clock_object: &Clock,
    coin_value: u64,
    ctx: &mut TxContext
  ) {
    let sender = tx_context::sender(ctx);
    // Unstake yields Coin<IPX> rewards.
    let (coin_ipx, coin) = master_chef::unstake<T>(
        storage,
        accounts_storage,
        ipx_storage,
        clock_object,
        coin_value,
        ctx
    );
    transfer::public_transfer(coin_ipx, sender);
    transfer::public_transfer(coin, sender);
  }

/**
* @notice It allows a user to withdraw his/her rewards from a specific farm. 
* @param storage The MasterChefStorage shared object
* @param accounts_storage The AccountStorage shared object
* @param ipx_storage The shared Object of IPX
* @param clock_object The Clock object created at genesis
*/
  entry public fun get_rewards<T>(
    storage: &mut MasterChefStorage,
    accounts_storage: &mut AccountStorage,
    ipx_storage: &mut IPXStorage,
    clock_object: &Clock,
    ctx: &mut TxContext   
  ) {
    transfer::public_transfer(master_chef::get_rewards<T>(storage, accounts_storage, ipx_storage, clock_object, ctx) ,tx_context::sender(ctx));
  }

/**
* @notice It updates the Coin<T> farm rewards calculation.
* @param storage The MasterChefStorage shared object
* @param clock_object The Clock object created at genesis
*/
  entry public fun update_pool<T>(storage: &mut MasterChefStorage, clock_object: &Clock) {
    master_chef::update_pool<T>(storage, clock_object);
  }

/**
* @notice It updates all pools.
* @param storage The MasterChefStorage shared object
* @param clock_object The Clock object created at genesis
*/
  entry public fun update_all_pools(storage: &mut MasterChefStorage, clock_object: &Clock) {
    master_chef::update_all_pools(storage, clock_object);
  }

/**
* @notice It allows a user to burn Coin<IPX>.
* @param storage The storage of the module ipx::ipx 
* @param coin_ipx The Coin<IPX>
*/
  entry public fun burn_ipx(
    storage: &mut IPXStorage,
    coin_ipx: Coin<IPX>
  ) {
    // Create a coin from the vector. It keeps the desired amound and sends any extra coins to the caller
    // vector total value - coin desired value
    ipx::burn(storage, coin_ipx);
  }

  public fun get_pool_id<C, X, Y>(storage: &Storage): ID {
    if (are_coins_sorted<X, Y>()) {
      dex::get_pool_id<C, X, Y>(storage)
    } else {
      dex::get_pool_id<C, Y, X>(storage)
    }
  }

  fun get_farm<X>(
    storage: &MasterChefStorage,
    accounts_storage: &AccountStorage,
    account: address,
    farm_vector: &mut vector<vector<u64>>
  ) {
     let inner_vector = vector::empty<u64>();
    let (allocation, _, _, pool_balance) = master_chef::get_pool_info<X>(storage);

    vector::push_back(&mut inner_vector, allocation);
    vector::push_back(&mut inner_vector, pool_balance);

    if (master_chef::account_exists<X>(storage, accounts_storage, account)) {
      let (account_balance, _) = master_chef::get_account_info<X>(storage, accounts_storage, account);
      vector::push_back(&mut inner_vector, account_balance);
    } else {
      vector::push_back(&mut inner_vector, 0);
    };

    vector::push_back(farm_vector, inner_vector);
  }

  public fun get_farms<A, B, C, D, E, F, G, H, I, J>(
    storage: &MasterChefStorage,
    accounts_storage: &AccountStorage,
    account: address,
    num_of_farms: u64
  ): vector<vector<u64>> {
    let farm_vector = vector::empty<vector<u64>>(); 

    get_farm<A>(storage, accounts_storage, account, &mut farm_vector);

    if (num_of_farms == 1) return farm_vector;

    get_farm<B>(storage, accounts_storage, account, &mut farm_vector);

    if (num_of_farms == 2) return farm_vector;

    get_farm<C>(storage, accounts_storage, account, &mut farm_vector);

    if (num_of_farms == 3) return farm_vector;

    get_farm<D>(storage, accounts_storage, account, &mut farm_vector);

    if (num_of_farms == 4) return farm_vector;

    get_farm<E>(storage, accounts_storage, account, &mut farm_vector);

    if (num_of_farms == 5) return farm_vector;

    get_farm<F>(storage, accounts_storage, account, &mut farm_vector);

    if (num_of_farms == 6) return farm_vector;

    get_farm<G>(storage, accounts_storage, account, &mut farm_vector);

    if (num_of_farms == 7) return farm_vector;

    get_farm<H>(storage, accounts_storage, account, &mut farm_vector);

    if (num_of_farms == 8) return farm_vector;

    get_farm<I>(storage, accounts_storage, account, &mut farm_vector);

    if (num_of_farms == 9) return farm_vector;

    get_farm<J>(storage, accounts_storage, account, &mut farm_vector);

    farm_vector
  }

  fun get_pool<C, X, Y>(storage: &Storage, pool_vector: &mut vector<vector<u64>>) {
      let inner_vector = vector::empty<u64>();
    let (balance_x, balance_y, supply) = dex::get_pool_info<C, X, Y>(storage);

    vector::push_back(&mut inner_vector, balance_x);
    vector::push_back(&mut inner_vector, balance_y);
    vector::push_back(&mut inner_vector, supply);
    vector::push_back(pool_vector, inner_vector);
  }

  public fun get_pools<
    Curve1 ,A1, A2, Curve2, B1, B2, Curve3, C1, C2, Curve4, D1, D2, Curve5, E1, E2, Curve6, F1, F2, Curve7, G1, G2, Curve8, H1, H2, Curve9, I1, I2, Curve10, J1, J2>(storage: &Storage, num_of_pools: u64): vector<vector<u64>> {
    let pool_vector = vector::empty<vector<u64>>(); 

    get_pool<Curve1, A1, A2>(storage, &mut pool_vector);

    if (num_of_pools == 1) return pool_vector;

    get_pool<Curve2, B1, B2>(storage, &mut pool_vector);

    if (num_of_pools == 2) return pool_vector;

    get_pool<Curve3, C1, C2>(storage, &mut pool_vector);

    if (num_of_pools == 3) return pool_vector;

    get_pool<Curve4, D1, D2>(storage, &mut pool_vector);

    if (num_of_pools == 4) return pool_vector;

    get_pool<Curve5, E1, E2>(storage, &mut pool_vector);

    if (num_of_pools == 5) return pool_vector;

    get_pool<Curve6, F1, F2>(storage, &mut pool_vector);

    if (num_of_pools == 6) return pool_vector;

    get_pool<Curve7, G1, G2>(storage, &mut pool_vector);

    if (num_of_pools == 7) return pool_vector;

    get_pool<Curve8, H1, H2>(storage, &mut pool_vector);

    if (num_of_pools == 8) return pool_vector;

    get_pool<Curve9, I1, I2>(storage, &mut pool_vector);

    if (num_of_pools == 9) return pool_vector;

    get_pool<Curve10, J1, J2>(storage, &mut pool_vector);

    pool_vector
  }
}