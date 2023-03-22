module interest_protocol::interface {
  use std::vector;

  use sui::coin::{Coin, CoinMetadata};
  use sui::tx_context::{Self, TxContext};
  use sui::transfer;
  use sui::clock::{Self, Clock};
  use sui::object::{ID};

  use interest_protocol::dex_volatile::{Self as volatile, Storage as VStorage, VLPCoin};
  use interest_protocol::dex_stable::{Self as stable, Storage as SStorage, SLPCoin};
  use interest_protocol::master_chef::{Self, MasterChefStorage, AccountStorage};
  use interest_protocol::ipx::{Self, IPXStorage, IPX};
  use interest_protocol::utils::{destroy_zero_or_transfer, handle_coin_vector, are_coins_sorted};
  use interest_protocol::router;

  const ERROR_TX_DEADLINE_REACHED: u64 = 1;

  /**
  * @dev This function does not require the coins to be sorted. It will send back any unused value. 
  * It create a volatile Pool with Coins X and Y
  * @param storage The storage object of the ipx::dex_volatile 
  * @param vector_x A vector of several Coin<X> 
  * @param vector_y A vector of several Coin<Y> 
  * @param coin_x_amount The value the caller wishes to deposit for Coin<X> 
  * @param coin_y_amount The value the caller wishes to deposit for Coin<Y>
  */
  entry public fun create_v_pool<X, Y>(
      storage: &mut VStorage,
      vector_x: vector<Coin<X>>,
      vector_y: vector<Coin<Y>>,
      coin_x_amount: u64,
      coin_y_amount: u64,
      ctx: &mut TxContext
  ) {
    
    // Create a coin from the vector. It keeps the desired amound and sends any extra coins to the caller
    // vector total value - coin desired value
    let coin_x = handle_coin_vector<X>(vector_x, coin_x_amount, ctx);
    let coin_y = handle_coin_vector<Y>(vector_y, coin_y_amount, ctx);

    // Sorts for the caller - to make it easier for the frontend
    if (are_coins_sorted<X, Y>()) {
      transfer::transfer(
        volatile::create_pool(
          storage,
          coin_x,
          coin_y,
          ctx
        ),
        tx_context::sender(ctx)
      )
    } else {
      transfer::transfer(
        volatile::create_pool(
          storage,
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
  * @param storage The storage object of the ipx::dex_volatile 
  * @param vector_x A vector of several Coin<X> 
  * @param vector_y A vector of several Coin<Y> 
  * @param coin_x_metadata The CoinMetadata object of Coin<X>
  * @param coin_y_metadata The CoinMetadata object of Coin<Y>
  * @param coin_x_amount The value the caller wishes to deposit for Coin<X> 
  * @param coin_y_amount The value the caller wishes to deposit for Coin<Y>
  */
  entry public fun create_s_pool<X, Y>(
      storage: &mut SStorage,
      vector_x: vector<Coin<X>>,
      vector_y: vector<Coin<Y>>,
      coin_x_metadata: &CoinMetadata<X>,
      coin_y_metadata: &CoinMetadata<Y>,
      coin_x_amount: u64,
      coin_y_amount: u64,
      ctx: &mut TxContext
  ) {
    
    // Create a coin from the vector. It keeps the desired amound and sends any extra coins to the caller
    // vector total value - coin desired value
    let coin_x = handle_coin_vector<X>(vector_x, coin_x_amount, ctx);
    let coin_y = handle_coin_vector<Y>(vector_y, coin_y_amount, ctx);

    // Sorts for the caller - to make it easier for the frontend
    if (are_coins_sorted<X, Y>()) {
      transfer::transfer(
        stable::create_pool(
          storage,
          coin_x,
          coin_y,
          coin_x_metadata,
          coin_y_metadata,
          ctx
        ),
        tx_context::sender(ctx)
      )
    } else {
      transfer::transfer(
        stable::create_pool(
          storage,
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
  * @param v_storage The storage object of the ipx::dex_volatile 
  * @param s_storage The storage object of the ipx::dex_stable 
  * @param clock_object The shared Clock object
  * @param vector_x A vector of several Coin<X> 
  * @param vector_y A vector of several Coin<Y> 
  * @param coin_x_amount The value the caller wishes to deposit for Coin<X> 
  * @param coin_y_amount The value the caller wishes to deposit for Coin<Y>
  * @param coin_out_min_value The minimum value the caller expects to receive to protect agaisnt slippage
  * @param deadline Timestamp indicating the deadline for this TX to be submitted
  */
  entry public fun swap<X, Y>(
    v_storage: &mut VStorage,
    s_storage: &mut SStorage,
    clock_object: &Clock,
    vector_x: vector<Coin<X>>,
    vector_y: vector<Coin<Y>>,
    coin_x_amount: u64,
    coin_y_amount: u64,
    coin_out_min_value: u64,
    deadline: u64,
    ctx: &mut TxContext
  ) {
    assert!(deadline >= clock::timestamp_ms(clock_object), ERROR_TX_DEADLINE_REACHED);
    // Create a coin from the vector. It keeps the desired amound and sends any extra coins to the caller
    // vector total value - coin desired value
    let coin_x = handle_coin_vector<X>(vector_x, coin_x_amount, ctx);
    let coin_y = handle_coin_vector<Y>(vector_y, coin_y_amount, ctx);

  if (are_coins_sorted<X, Y>()) {
   let (coin_x, coin_y) = router::swap<X, Y>(
      v_storage,
      s_storage,
      coin_x,
      coin_y,
      coin_out_min_value,
      ctx
    );

    destroy_zero_or_transfer(coin_x, ctx);
    destroy_zero_or_transfer(coin_y, ctx);
    } else {
    let (coin_y, coin_x) = router::swap<Y, X>(
      v_storage,
      s_storage,
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
  * @param v_storage The storage object of the ipx::dex_volatile 
  * @param s_storage The storage object of the ipx::dex_stable 
  * @param clock_object The shared Clock object
  * @param vector_x A vector of several Coin<X> 
  * @param vector_y A vector of several Coin<Y> 
  * @param coin_x_amount The value the caller wishes to deposit for Coin<X> 
  * @param coin_y_amount The value the caller wishes to deposit for Coin<Y>
  * @param coin_out_min_value The minimum value the caller expects to receive to protect agaisnt slippage
  * @param deadline Timestamp indicating the deadline for this TX to be submitted
  */
  entry public fun one_hop_swap<X, Y, Z>(
    v_storage: &mut VStorage,
    s_storage: &mut SStorage,
    clock_object: &Clock,
    vector_x: vector<Coin<X>>,
    vector_y: vector<Coin<Y>>,
    coin_x_amount: u64,
    coin_y_amount: u64,
    coin_out_min_value: u64,
    deadline: u64,
    ctx: &mut TxContext
  ) {
    assert!(deadline >= clock::timestamp_ms(clock_object), ERROR_TX_DEADLINE_REACHED);
    // Create a coin from the vector. It keeps the desired amound and sends any extra coins to the caller
    // vector total value - coin desired value
    let coin_x = handle_coin_vector<X>(vector_x, coin_x_amount, ctx);
    let coin_y = handle_coin_vector<Y>(vector_y, coin_y_amount, ctx);

    let (coin_x, coin_y) = router::one_hop_swap<X, Y, Z>(
      v_storage,
      s_storage,
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
  * @param v_storage The storage object of the ipx::dex_volatile 
  * @param s_storage The storage object of the ipx::dex_stable 
  * @param clock_object The shared Clock object
  * @param vector_x A vector of several Coin<X> 
  * @param vector_y A vector of several Coin<Y> 
  * @param coin_x_amount The value the caller wishes to deposit for Coin<X> 
  * @param coin_y_amount The value the caller wishes to deposit for Coin<Y>
  * @param coin_out_min_value The minimum value the caller expects to receive to protect agaisnt slippage
  * @param deadline Timestamp indicating the deadline for this TX to be submitted
  */
  entry public fun two_hop_swap<X, Y, B1, B2>(
    v_storage: &mut VStorage,
    s_storage: &mut SStorage,
    clock_object: &Clock,
    vector_x: vector<Coin<X>>,
    vector_y: vector<Coin<Y>>,
    coin_x_amount: u64,
    coin_y_amount: u64,
    coin_out_min_value: u64,
    deadline: u64,
    ctx: &mut TxContext
  ) {
    assert!(deadline >= clock::timestamp_ms(clock_object), ERROR_TX_DEADLINE_REACHED);
    // Create a coin from the vector. It keeps sends any extra coins to the caller
    // vector total value - coin desired value
    let coin_x = handle_coin_vector<X>(vector_x, coin_x_amount, ctx);
    let coin_y = handle_coin_vector<Y>(vector_y, coin_y_amount, ctx);

    let (coin_x, coin_y) = router::two_hop_swap<X, Y, B1, B2>(
      v_storage,
      s_storage,
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
  * @param v_storage The storage object of the ipx::dex_volatile 
  * @param s_storage The storage object of the ipx::dex_stable 
  * @param vector_x A vector of several Coin<X> 
  * @param vector_y A vector of several Coin<Y> 
  * @param coin_x_amount The value the caller wishes to deposit for Coin<X> 
  * @param coin_y_amount The value the caller wishes to deposit for Coin<Y>
  * @param is_volatile It indicates if it should add liquidity a stable or volatile pool
  * @param coin_out_min_value The minimum value the caller expects to receive to protect agaisnt slippage
  */
  entry public fun add_liquidity<X, Y>(
    v_storage: &mut VStorage,
    s_storage: &mut SStorage,
    vector_x: vector<Coin<X>>,
    vector_y: vector<Coin<Y>>,
    coin_x_amount: u64,
    coin_y_amount: u64,
    is_volatile: bool,
    coin_min_amount: u64,
    ctx: &mut TxContext
  ) {

    // Create a coin from the vector. It keeps the desired amound and sends any extra coins to the caller
    // vector total value - coin desired value
    let coin_x = handle_coin_vector<X>(vector_x, coin_x_amount, ctx);
    let coin_y = handle_coin_vector<Y>(vector_y, coin_y_amount, ctx);

    if (is_volatile) {
      if (are_coins_sorted<X, Y>()) {
        transfer::transfer(
          router::add_v_liquidity(
          v_storage,
          coin_x,
          coin_y,
          coin_min_amount,
          ctx
          ),
        tx_context::sender(ctx)
      )  
      } else {
        transfer::transfer(
          router::add_v_liquidity(
          v_storage,
          coin_y,
          coin_x,
          coin_min_amount,
          ctx
          ),
        tx_context::sender(ctx)
      )  
      }
      } else {
        if (are_coins_sorted<X, Y>()) {
          transfer::transfer(
            router::add_s_liquidity(
            s_storage,
            coin_x,
            coin_y,
            coin_min_amount,
            ctx
            ),
          tx_context::sender(ctx)
        )  
        } else {
          transfer::transfer(
            router::add_s_liquidity(
            s_storage,
            coin_x,
            coin_y,
            coin_min_amount,
            ctx
            ),
          tx_context::sender(ctx)
        )  
      }
    }
  }

  /**
  * @dev This function REQUIRES the coins to be sorted. It will send back any unused value. 
  * It removes liquidity from a volatile pool based on the shares
  * @param storage The storage object of the ipx::dex_volatile 
  * @param vector_lp_coin A vector of several VLPCoins
  * @param coin_amount_in The value the caller wishes to deposit for VLPCoins 
  * @param coin_x_min_amount The minimum amount of Coin<X> the user wishes to receive
  * @param coin_y_min_amount The minimum amount of Coin<Y> the user wishes to receive
  */
  entry public fun remove_v_liquidity<X, Y>(
    storage: &mut VStorage,
    vector_lp_coin: vector<Coin<VLPCoin<X, Y>>>,
    coin_amount_in: u64,
    coin_x_min_amount: u64,
    coin_y_min_amount: u64,
    ctx: &mut TxContext
  ){
    // Create a coin from the vector. It keeps the desired amound and sends any extra coins to the caller
    // vector total value - coin desired value
    let coin = handle_coin_vector(vector_lp_coin, coin_amount_in, ctx);
    let sender = tx_context::sender(ctx);

    let (coin_x, coin_y) = volatile::remove_liquidity(
      storage,
      coin, 
      coin_x_min_amount,
      coin_y_min_amount,
      ctx
    );

    transfer::transfer(coin_x, sender);
    transfer::transfer(coin_y, sender);
  }

  /**
  * @dev This function REQUIRES the coins to be sorted. It will send back any unused value. 
  * It removes liquidity from a stable pool based on the shares
  * @param storage The storage object of the ipx::dex_volatile 
  * @param vector_lp_coin A vector of several SLPCoins
  * @param coin_amount_in The value the caller wishes to deposit for VLPCoins 
  * @param coin_x_min_amount The minimum amount of Coin<X> the user wishes to receive
  * @param coin_y_min_amount The minimum amount of Coin<Y> the user wishes to receive
  */
  entry public fun remove_s_liquidity<X, Y>(
    storage: &mut SStorage,
    vector_lp_coin: vector<Coin<SLPCoin<X, Y>>>,
    coin_amount_in: u64,
    coin_x_min_amount: u64,
    coin_y_min_amount: u64,
    ctx: &mut TxContext
  ){
    // Create a coin from the vector. It keeps the desired amound and sends any extra coins to the caller
    // vector total value - coin desired value
    let coin = handle_coin_vector(vector_lp_coin, coin_amount_in, ctx);
    let sender = tx_context::sender(ctx);

    let (coin_x, coin_y) = stable::remove_liquidity(
      storage,
      coin, 
      coin_x_min_amount,
      coin_y_min_amount,
      ctx
    );

    transfer::transfer(coin_x, sender);
    transfer::transfer(coin_y, sender);
  }

/**
* @notice It allows a user to deposit a Coin<T> in a farm to earn Coin<IPX>. 
* @param storage The MasterChefStorage shared object
* @param accounts_storage The AccountStorage shared object
* @param ipx_storage The shared Object of IPX
* @param clock_object The Clock object created at genesis
* @param coin_vector A vector of Coin<T>
* @param coin_value The value of Coin<T> the caller wishes to deposit  
*/
  entry public fun stake<T>(
    storage: &mut MasterChefStorage,
    accounts_storage: &mut AccountStorage,
    ipx_storage: &mut IPXStorage,
    clock_object: &Clock,
    coin_vector: vector<Coin<T>>,
    coin_value: u64,
    ctx: &mut TxContext
  ) {
    // Create a coin from the vector. It keeps the desired amound and sends any extra coins to the caller
    // vector total value - coin desired value
    let coin = handle_coin_vector(coin_vector, coin_value, ctx);

    // Stake and send Coin<IPX> rewards to the caller.
    transfer::transfer(
      master_chef::stake(
        storage,
        accounts_storage,
        ipx_storage,
        clock_object,
        coin,
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
    transfer::transfer(coin_ipx, sender);
    transfer::transfer(coin, sender);
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
    transfer::transfer(master_chef::get_rewards<T>(storage, accounts_storage, ipx_storage, clock_object, ctx) ,tx_context::sender(ctx));
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
* @param coin_vector A vector of Coin<IPX>
* @param coin_value The value of Coin<IPX> the caller wishes to burn 
*/
  entry public fun burn_ipx(
    storage: &mut IPXStorage,
    coin_vector: vector<Coin<IPX>>,
    coin_value: u64,
    ctx: &mut TxContext
  ) {
    // Create a coin from the vector. It keeps the desired amound and sends any extra coins to the caller
    // vector total value - coin desired value
    ipx::burn(storage, handle_coin_vector(coin_vector, coin_value, ctx));
  }

  public fun get_v_pool_id<X, Y>(storage: &VStorage): ID {
    if (are_coins_sorted<X, Y>()) {
      volatile::get_pool_id<X, Y>(storage)
    } else {
      volatile::get_pool_id<Y, X>(storage)
    }
  }

  public fun get_s_pool_id<X, Y>(storage: &SStorage): ID {
    if (are_coins_sorted<X, Y>()) {
      stable::get_pool_id<X, Y>(storage)
    } else {
      stable::get_pool_id<Y, X>(storage)
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

  fun get_v_pool<X, Y>(storage: &VStorage, pool_vector: &mut vector<vector<u64>>) {
      let inner_vector = vector::empty<u64>();
    let (balance_x, balance_y, supply) = volatile::get_pool_info<X, Y>(storage);

    vector::push_back(&mut inner_vector, balance_x);
    vector::push_back(&mut inner_vector, balance_y);
    vector::push_back(&mut inner_vector, supply);
    vector::push_back(pool_vector, inner_vector);
  }

  public fun get_v_pools<A1, A2, B1, B2, C1, C2, D1, D2, E1, E2, F1, F2, G1, G2, H1, H2, I1, I2, J1, J2>(storage: &VStorage, num_of_pools: u64): vector<vector<u64>> {
    let pool_vector = vector::empty<vector<u64>>(); 

    get_v_pool<A1, A2>(storage, &mut pool_vector);

    if (num_of_pools == 1) return pool_vector;

    get_v_pool<B1, B2>(storage, &mut pool_vector);

    if (num_of_pools == 2) return pool_vector;

    get_v_pool<C1, C2>(storage, &mut pool_vector);

    if (num_of_pools == 3) return pool_vector;

    get_v_pool<D1, D2>(storage, &mut pool_vector);

    if (num_of_pools == 4) return pool_vector;

    get_v_pool<E1, E2>(storage, &mut pool_vector);

    if (num_of_pools == 5) return pool_vector;

    get_v_pool<F1, F2>(storage, &mut pool_vector);

    if (num_of_pools == 6) return pool_vector;

    get_v_pool<G1, G2>(storage, &mut pool_vector);

    if (num_of_pools == 7) return pool_vector;

    get_v_pool<H1, H2>(storage, &mut pool_vector);

    if (num_of_pools == 8) return pool_vector;

    get_v_pool<I1, I2>(storage, &mut pool_vector);

    if (num_of_pools == 9) return pool_vector;

    get_v_pool<J1, J2>(storage, &mut pool_vector);

    pool_vector
  }
}