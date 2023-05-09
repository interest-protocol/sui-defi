// Entry functions for Interest Protocol
module dex::interface {
  use std::vector;

  use sui::coin::{Coin, CoinMetadata};
  use sui::tx_context::{Self, TxContext};
  use sui::transfer;
  use sui::clock::{Self, Clock};
  use sui::object::{ID};

  use dex::router;
  use dex::core::{Self, DEXStorage, LPCoin};
  use dex::master_chef::{Self, MasterChefStorage, AccountStorage as MasterChefAccountStorage};

  use ipx::ipx::{Self, IPXStorage, IPX};
  
  use library::utils::{handle_coin_vector, are_coins_sorted};

  const ERROR_TX_DEADLINE_REACHED: u64 = 1;

  /**
  * @dev This function does not require the coins to be sorted. It will send back any unused value. 
  * It create a volatile Pool with Coins X and Y
  * @param storage The DEXStorage object of the interest_protocol::dex 
  * @param clock_object The shared Clock object at id @0x6
  * @param vector_x  A list of Coin<X>, the contract will merge all coins into with the `coin_x_amount` and return any extra value
  * @param vector_y  A list of Coin<Y>, the contract will merge all coins into with the `coin_y_amount` and return any extra value 
  * @param coin_x_amount The desired amount of Coin<X> to send
  * @param coin_y_amount The desired amount of Coin<Y> to send
  */
  entry public fun create_v_pool<X, Y>(
      storage: &mut DEXStorage,
      clock_object: &Clock,
      vector_x: vector<Coin<X>>,
      vector_y: vector<Coin<Y>>,
      coin_x_amount: u64,
      coin_y_amount: u64,
      ctx: &mut TxContext
  ) {

    let coin_x = handle_coin_vector<X>(vector_x, coin_x_amount, ctx);
    let coin_y = handle_coin_vector<Y>(vector_y, coin_y_amount, ctx);

    // Sorts for the caller - to make it easier for the frontend
    if (are_coins_sorted<X, Y>()) {
      transfer::public_transfer(
        core::create_v_pool(
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
        core::create_v_pool(
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
  * @param storage The DEXStorage object of the interest_protocol::dex
  * @param clock_object The shared Clock object at id @0x6
  * @param vector_x  A list of Coin<X>, the contract will merge all coins into with the `coin_x_amount` and return any extra value
  * @param vector_y  A list of Coin<Y>, the contract will merge all coins into with the `coin_y_amount` and return any extra value 
  * @param coin_x_amount The desired amount of Coin<X> to send
  * @param coin_y_amount The desired amount of Coin<Y> to send
  * @param coin_x_metadata The metadata oject of Coin<X>
  * @param coin_y_metadata The metadata oject of Coin<Y>
  */
  entry public fun create_s_pool<X, Y>(
      storage: &mut DEXStorage,
      clock_object: &Clock,
      vector_x: vector<Coin<X>>,
      vector_y: vector<Coin<Y>>,
      coin_x_amount: u64,
      coin_y_amount: u64,
      coin_x_metadata: &CoinMetadata<X>,
      coin_y_metadata: &CoinMetadata<Y>,
      ctx: &mut TxContext
  ) {

    let coin_x = handle_coin_vector<X>(vector_x, coin_x_amount, ctx);
    let coin_y = handle_coin_vector<Y>(vector_y, coin_y_amount, ctx);

    // Sorts for the caller - to make it easier for the frontend
    if (are_coins_sorted<X, Y>()) {
      transfer::public_transfer(
        core::create_s_pool(
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
        core::create_s_pool(
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
  * @dev This function requires the tokens to be sorted
  * It performs a swap and finds the most profitable pool. X -> Y on Pool<X, Y>
  * @param storage The DEXStorage object of the interest_protocol::dex
  * @param clock_object The shared Clock object at id @0x6
  * @param vector_x A vector of several Coin<X> 
  * @param coin_x_amount The value the caller wishes to deposit for Coin<X> 
  * @param coin_out_min_value The minimum value the caller expects to receive to protect agaisnt slippage
  * @param deadline The TX must be submitted before this timestamp
  */
  entry public fun swap_x<X, Y>(
    storage: &mut DEXStorage,
    clock_object: &Clock,
    vector_x: vector<Coin<X>>,
    coin_x_amount: u64,
    coin_out_min_value: u64,
    deadline: u64,
    ctx: &mut TxContext
  ) {
    assert!(deadline >= clock::timestamp_ms(clock_object), ERROR_TX_DEADLINE_REACHED);

    // Create a coin from the vector. It keeps the desired amound and sends any extra coins to the caller
    // vector total value - coin desired value
    let coin_x = handle_coin_vector<X>(vector_x, coin_x_amount, ctx);

    transfer::public_transfer(
      router::swap_token_x<X, Y>(
      storage,
      clock_object,
      coin_x,
      coin_out_min_value,
      ctx
      ),
      tx_context::sender(ctx)
    );
  }

  /**
  * @dev This function requires the tokens to be sorted
  * It performs a swap and finds the most profitable pool. Y -> X on Pool<X, Y>
  * @param storage The DEXStorage object of the interest_protocol::dex
  * @param clock_object The shared Clock object at id @0x6
  * @param vector_y A vector of several Coin<Y> 
  * @param coin_y_amount The value the caller wishes to deposit for Coin<Y>
  * @param coin_out_min_value The minimum value the caller expects to receive to protect agaisnt slippage
  * @param deadline The TX must be submitted before this timestamp
  */
  entry public fun swap_y<X, Y>(
    storage: &mut DEXStorage,
    clock_object: &Clock,
    vector_y: vector<Coin<Y>>,
    coin_y_amount: u64,
    coin_out_min_value: u64,
    deadline: u64,
    ctx: &mut TxContext
  ) {
    assert!(deadline >= clock::timestamp_ms(clock_object), ERROR_TX_DEADLINE_REACHED);
    // Create a coin from the vector. It keeps the desired amound and sends any extra coins to the caller
    // vector total value - coin desired value
    let coin_y = handle_coin_vector<Y>(vector_y, coin_y_amount, ctx);

    transfer::public_transfer(
      router::swap_token_y<X, Y>(
      storage,
      clock_object,
      coin_y,
      coin_out_min_value,
      ctx
      ),
      tx_context::sender(ctx)
    );
  }


  /**
  * @dev This function does not require the coins to be sorted. It will send back any unused value. 
  * It performs an one hop swap and finds the most profitable pool. X -> B -> Y on Pool<X, B> -> Pool<B, Y>
  * @param storage The DEXStorage object of the interest_protocol::dex
  * @param clock_object The shared Clock object
  * @param vector_x A vector of several Coin<X> 
  * @param coin_x_amount The value the caller wishes to deposit for Coin<X> 
  * @param coin_out_min_value The minimum value the caller expects to receive to protect agaisnt slippage
  * @param deadline Timestamp indicating the deadline for this TX to be submitted
  */
  entry public fun one_hop_swap<X, B, Y>(
    storage: &mut DEXStorage,
    clock_object: &Clock,
    vector_x: vector<Coin<X>>,
    coin_x_amount: u64,
    coin_out_min_value: u64,
    deadline: u64,
    ctx: &mut TxContext
  ) {
    assert!(deadline >= clock::timestamp_ms(clock_object), ERROR_TX_DEADLINE_REACHED);

    // Create a coin from the vector. It keeps the desired amound and sends any extra coins to the caller
    // vector total value - coin desired value
    let coin_x = handle_coin_vector<X>(vector_x, coin_x_amount, ctx);

    transfer::public_transfer(
      router::one_hop_swap<X, B, Y>(
      storage,
      clock_object,
      coin_x,
      coin_out_min_value,
      ctx
      ),
      tx_context::sender(ctx)
    )
  }

  /**
  * @dev This function does not require the coins to be sorted. It will send back any unused value. 
  * It performs a three hop swap and finds the most profitable pool. X -> B1 -> B2 -> Y or Y -> B1 -> B2 -> X on Pool<X, Z> -> Pool<B1, B2> -> Pool<B2, Y>
  * @param storage The DEXStorage object of the interest_protocol::dex  
  * @param clock_object The shared Clock object
  * @param vector_x A vector of several Coin<X> 
  * @param coin_x_amount The value the caller wishes to deposit for Coin<X> 
  * @param coin_out_min_value The minimum value the caller expects to receive to protect agaisnt slippage
  * @param deadline Timestamp indicating the deadline for this TX to be submitted
  */
  entry public fun two_hop_swap<X, B1, B2, Y>(
    storage: &mut DEXStorage,
    clock_object: &Clock,
    vector_x: vector<Coin<X>>,
    coin_x_amount: u64,
    coin_out_min_value: u64,
    deadline: u64,
    ctx: &mut TxContext
  ) {
    assert!(deadline >= clock::timestamp_ms(clock_object), ERROR_TX_DEADLINE_REACHED);

    // Create a coin from the vector. It keeps the desired amound and sends any extra coins to the caller
    // vector total value - coin desired value
    let coin_x = handle_coin_vector<X>(vector_x, coin_x_amount, ctx);

    transfer::public_transfer(
      router::two_hop_swap<X, B1, B2, Y>(
      storage,
      clock_object,
      coin_x,
      coin_out_min_value,
      ctx
      ),
      tx_context::sender(ctx)
    )
  }

  /**
  * @dev This function does not require the coins to be sorted. It will send back any unused value. 
  * It adds liquidity to a Pool
  * @param storage The DEXStorage object of the interest_protocol::dex  
  * @param clock_object The shared Clock object
  * @param vector_x  A list of Coin<X>, the contract will merge all coins into with the `coin_x_amount` and return any extra value
  * @param vector_y  A list of Coin<Y>, the contract will merge all coins into with the `coin_y_amount` and return any extra value 
  * @param coin_x_amount The desired amount of Coin<X> to send
  * @param coin_y_amount The desired amount of Coin<Y> to send
  * @param coin_out_min_value The minimum value the caller expects to receive to protect agaisnt slippage
  */
  entry public fun add_liquidity<C, X, Y>(
    storage: &mut DEXStorage,
    clock_object: &Clock,
    vector_x: vector<Coin<X>>,
    vector_y: vector<Coin<Y>>,
    coin_x_amount: u64,
    coin_y_amount: u64,
    coin_min_amount: u64,
    ctx: &mut TxContext
  ) {

    // Create a coin from the vector. It keeps the desired amound and sends any extra coins to the caller
    // vector total value - coin desired value
    let coin_x = handle_coin_vector<X>(vector_x, coin_x_amount, ctx);
    let coin_y = handle_coin_vector<Y>(vector_y, coin_y_amount, ctx);

      if (are_coins_sorted<X, Y>()) {
        transfer::public_transfer(
          core::add_liquidity<C, X, Y>(
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
          core::add_liquidity<C, Y, X>(
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
  * @param storage The DEXStorage object of the interest_protocol::dex 
  * @param clock_object The shared Clock object
  * @param vector_lp_coin A vector of several VLPCoins
  * @param lp_coin_amount The value the caller wishes to deposit for VLPCoins 
  * @param coin_x_min_amount The minimum amount of Coin<X> the user wishes to receive
  * @param coin_y_min_amount The minimum amount of Coin<Y> the user wishes to receive
  */
  entry public fun remove_liquidity<C, X, Y>(
    storage: &mut DEXStorage,
    clock_object: &Clock,
    vector_lp_coin: vector<Coin<LPCoin<C, X, Y>>>,
    lp_coin_amount: u64,
    coin_x_min_amount: u64,
    coin_y_min_amount: u64,
    ctx: &mut TxContext
  ){
    let sender = tx_context::sender(ctx);

    // Create a coin from the vector. It keeps the desired amound and sends any extra coins to the caller
    // vector total value - coin desired value
    let lp_coin = handle_coin_vector<LPCoin<C, X, Y>>(vector_lp_coin, lp_coin_amount, ctx);

    let (coin_x, coin_y) = core::remove_liquidity(
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
* @param accounts_storage The MasterChefAccountStorage shared object
* @param ipx_storage The shared Object of IPX
* @param clock_object The Clock object created at genesis
* @param vector_token  A list of Coin<Y>, the contract will merge all coins into with the `coin_y_amount` and return any extra value 
* @param coin_token_amount The desired amount of Coin<X> to send
*/
  entry public fun stake<T>(
    storage: &mut MasterChefStorage,
    accounts_storage: &mut MasterChefAccountStorage,
    ipx_storage: &mut IPXStorage,
    clock_object: &Clock,
    vector_token: vector<Coin<T>>,
    coin_token_amount: u64,
    ctx: &mut TxContext
  ) {

    // Create a coin from the vector. It keeps the desired amound and sends any extra coins to the caller
    // vector total value - coin desired value
    let token = handle_coin_vector<T>(vector_token, coin_token_amount, ctx);

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
* @param accounts_storage The MasterChefAccountStorage shared object
* @param ipx_storage The shared Object of IPX
* @param clock_object The Clock object created at genesis
* @param coin_value The amount of Coin<T> the caller wishes to withdraw
*/
  entry public fun unstake<T>(
    storage: &mut MasterChefStorage,
    accounts_storage: &mut MasterChefAccountStorage,
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
    accounts_storage: &mut MasterChefAccountStorage,
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

  /**
  * @dev It returns the ID of a pool so frontend clients can fetch using sui_getObject. It does not need to be oredered
  * @param storage The DEXStorage shared object from the interest_protocol::dex module 
  * @return the unique ID of a deployed pool
  */
  public fun get_pool_id<C, X, Y>(storage: &DEXStorage): ID {
    if (are_coins_sorted<X, Y>()) {
      core::get_pool_id<C, X, Y>(storage)
    } else {
      core::get_pool_id<C, Y, X>(storage)
    }
  }

  /**
  * @dev A utility function to return to the frontend the allocation, pool_balance and _account balance of farm for Coin<X>
  * @param storage The MasterChefStorage shared object
  * @param accounts_storage the MasterChefAccountStorage shared object of the masterchef contract
  * @param account The account of the user that has Coin<X> in the farm
  * @param farm_vector The list of farm data we will be mutation/adding
  */
  fun get_farm<X>(
    storage: &MasterChefStorage,
    accounts_storage: &MasterChefAccountStorage,
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

  /**
  * @dev The implementation of the get_farm function. It collects information for ${num_of_farms}.
  * @param storage The MasterChefStorage shared object
  * @param accounts_storage the MasterChefAccountStorage shared object of the masterchef contract
  * @param account The account of the user that has Coin<X> in the farm
  * @param num_of_farms The number of farms we wish to collect data from for a maximum of 3
  */
  public fun get_farms<A, B, C>(
    storage: &MasterChefStorage,
    accounts_storage: &MasterChefAccountStorage,
    account: address,
    num_of_farms: u64
  ): vector<vector<u64>> {
    let farm_vector = vector::empty<vector<u64>>(); 

    get_farm<A>(storage, accounts_storage, account, &mut farm_vector);

    if (num_of_farms == 1) return farm_vector;

    get_farm<B>(storage, accounts_storage, account, &mut farm_vector);

    if (num_of_farms == 2) return farm_vector;

    get_farm<C>(storage, accounts_storage, account, &mut farm_vector);

    farm_vector
  }
}