module interest_protocol::router {

  use sui::coin::{Self, Coin};
  use sui::tx_context::{Self, TxContext};
  use sui::pay;
  
  use interest_protocol::dex_volatile::{Self as volatile, Storage as VStorage, VLPCoin};
  use interest_protocol::dex_stable::{Self as stable, Storage as SStorage, SLPCoin};
  use interest_protocol::utils;

  const ERROR_ZERO_VALUE_SWAP: u64 = 1;
  const ERROR_POOL_NOT_DEPLOYED: u64 = 2;

  /**
  * @notice This fun calculates the most profitable pool and calls the fn with the same name on right module
  * It performs a swap: Coin<X> -> Coin<Y> on a Pool<X, Y>
  * @param v_storage the storage object of the ipx::dex_volatile module
  * @param s_storage the storage object of the ipx::dex_stable module
  * @param coin_x the Coin<X> the caller intends to sell 
  * @param coin_y_min_value the minimum amount of Coin<Y> the caller is willing to accept 
  * @return Coin<Y> the coin bought
  */
  fun swap_token_x<X, Y>(
      v_storage: &mut VStorage,
      s_storage: &mut SStorage,
      coin_x: Coin<X>,
      coin_y_min_value: u64,
      ctx: &mut TxContext
      ): Coin<Y> {
      if (is_volatile_better<X, Y>(v_storage, s_storage, coin::value(&coin_x), 0)) {
        volatile::swap_token_x(v_storage, coin_x, coin_y_min_value, ctx)
        } else {
        stable::swap_token_x(s_storage, coin_x, coin_y_min_value, ctx)
        }
    }

  /**
  * @notice This fun calculates the most profitable pool and calls the fn with the same name on right module
  * It performs a swap: Coin<Y> -> Coin<X> on a Pool<X, Y>
  * @param v_storage the storage object of the ipx::dex_volatile module
  * @param s_storage the storage object of the ipx::dex_stable module
  * @param coin_y the Coin<Y> the caller intends to sell 
  * @param coin_x_min_value the minimum amount of Coin<X> the caller is willing to accept 
  * @return Coin<X> the coin bought
  */
  fun swap_token_y<X, Y>(
      v_storage: &mut VStorage,
      s_storage: &mut SStorage,
      coin_y: Coin<Y>,
      coin_x_min_value: u64,
      ctx: &mut TxContext
      ): Coin<X> {
        if (is_volatile_better<X, Y>(v_storage, s_storage, 0, coin::value(&coin_y))) {
          volatile::swap_token_y(v_storage, coin_y, coin_x_min_value, ctx)
          } else {
          stable::swap_token_y(s_storage, coin_y, coin_x_min_value, ctx)
          }
    }

  /**
  * @dev This is a helper function to simplify the code. One of the coin values should be 0. 
  * If coin_x value is 0, it will swap Y -> X and vice versa.
  * @param v_storage the storage object of the ipx::dex_volatile module
  * @param s_storage the storage object of the ipx::dex_stable module
  * @param coin_x the Coin<X> of Pool<X, Y>
  * @param coin_x the Coin<Y> of Pool<X, Y>
  * @param coin_out_min_value the minimum amount of coin the caller is willing to accept 
  * @return (Coin<X>, Coin<Y>) One of the coins will have a value of 0. The one with the same type that was sold.
  */  
  public fun swap<X, Y>(
    v_storage: &mut VStorage,
    s_storage: &mut SStorage,
    coin_x: Coin<X>,
    coin_y: Coin<Y>,
    coin_out_min_value: u64,
    ctx: &mut TxContext
  ): (Coin<X>, Coin<Y>) {
    // If Coin<X> has a value of 0 do a Y -> X swap
    if (coin::value(&coin_x) == 0) {
      coin::destroy_zero(coin_x);
      (swap_token_y(
        v_storage,
        s_storage,
        coin_y,
        coin_out_min_value,
        ctx
      ), coin::zero<Y>(ctx)) 
    } else {
      coin::destroy_zero(coin_y);
      // If Coin<X> value is not 0 do a Y -> X swap
      (coin::zero<X>(ctx), swap_token_x(
        v_storage,
        s_storage,
        coin_x,
        coin_out_min_value,
        ctx
      ))
    }
  }  

  /**
  * @notice It performs a swap between two Pools. E.g., ETH -> BTC -> SUI (BTC/ETH) <> (BTC/SUI)
  * @param v_storage the storage object of the ipx::dex_volatile module
  * @param s_storage the storage object of the ipx::dex_stable module
  * @param coin_x if Coin<X> value is zero. The fn will perform this swap Y -> Z -> X 
  * @param coin_y if Coin<Y> value is zero. The fn will perform this swap X -> Z -> Y
  * @param coin_out_min_value the minimum final value accepted by the caller 
  * @return (Coin<X>, Coin<Y>) the type of the coin sold will have a value of 0
  */
  public fun one_hop_swap<X, Y, Z>(
    v_storage: &mut VStorage,
    s_storage: &mut SStorage,
    coin_x: Coin<X>,
    coin_y: Coin<Y>,
    coin_out_min_value: u64,
    ctx: &mut TxContext
  ): (Coin<X>, Coin<Y>) {
      // If Coin<X> value is zero this is a Y -> Z -> X swap; otherwise, it is a X -> Z -> Y swap
      let is_coin_x_value_zero = coin::value(&coin_x) == 0;

      // One of the coins must have a value greater than zero or we are wasting gas
      assert!(!is_coin_x_value_zero || coin::value(&coin_y) != 0, ERROR_ZERO_VALUE_SWAP);

      // Y -> Z -> X
      if (is_coin_x_value_zero) {
        coin::destroy_zero(coin_x);

        // We need to sort Y/Z to find the pool
        if (utils::are_coins_sorted<Y, Z>()) {
          // We sell Coin<Y> to buy Coin<Z>
          // Assuming Pool<Y, Z> we are selling the first token
          let coin_z = swap_token_x<Y, Z>(
             v_storage,
             s_storage,
             coin_y, 
             0, 
             ctx
            );

          // We need to sort X/Z to find the pool
          if (utils::are_coins_sorted<X, Z>()) {
            // We sell Coin<X> to buy Coin<X>
            // Assuming the Pool<X,Z>, we are selling the second
            let coin_x = swap_token_y(
              v_storage,
              s_storage,
              coin_z, 
              coin_out_min_value, 
              ctx
            );

            // Swap finished return
            (coin_x, coin::zero<Y>(ctx))
            
            } else {
            // We sell Coin<X> to buy Coin<X>
            // Assuming the Pool<Z, X>, we are selling the first token
            let coin_x = swap_token_x(
              v_storage,
              s_storage,
              coin_z, 
              coin_out_min_value, 
              ctx
            );
            
              // Swap finished return
             (coin_x, coin::zero<Y>(ctx))
            }
           } else {
            // We sell Coin<Y> to buy Coin<Z>
            // Assuming Pool<Z, Y> we are selling the second token
            let coin_z = swap_token_y<Z, Y>(
              v_storage,
              s_storage,
              coin_y, 
              0, 
              ctx
            );

          if (utils::are_coins_sorted<X, Z>()) {
            // We sell Coin<Z> to buy Coin<X>
            // Assuming Pool<X, Z> we are selling the second token
            let coin_x = swap_token_y(
              v_storage,
              s_storage,
              coin_z, 
              coin_out_min_value, 
              ctx
            );
            // Swap finished return
            (coin_x, coin::zero<Y>(ctx))
            
            } else {
              // We sell Coin<Z> to buy Coin<X>
            // Assuming Pool<Z, X> we are selling the first token
            let coin_x = swap_token_x(
              v_storage,
              s_storage,
              coin_z, 
              coin_out_min_value, 
              ctx
            );

            // Swap finished return
            (coin_x, coin::zero<Y>(ctx))
            }
           }

        // X -> Z -> Y
        } else {
            coin::destroy_zero(coin_y);

           if (utils::are_coins_sorted<X, Z>()) {
            // We sell Coin<X> -> Coin<Z>
            // In the Pool<Z, X> we are selling the first token
            let coin_z = swap_token_x<X, Z>(
              v_storage,
              s_storage,
              coin_x, 
              0, 
              ctx
            );

          if (utils::are_coins_sorted<Y, Z>()) {
            // We sell Coin<Z> -> Coin<Y>
            // In the Pool<Y, Z> we are selling the second token
            let coin_y = swap_token_y(
              v_storage,
              s_storage,
              coin_z, 
              coin_out_min_value, 
              ctx
            );

            // Swap ended
            (coin::zero<X>(ctx), coin_y)
            
            } else {
            // We sell Coin<Z> -> Coin<Y>
            // In the Pool<Z, Y> we are selling the first token
            let coin_y = swap_token_x(
              v_storage,
              s_storage,
              coin_z, 
              coin_out_min_value, 
              ctx
            );

             // Swap ended 
             (coin::zero<X>(ctx), coin_y)
            }
           } else {
            // We sell Coin<X> -> Coin<Z>
            // In the Pool<Z, X> we are selling the second token
            let coin_z = swap_token_y<Z, X>(
              v_storage,
              s_storage,
              coin_x, 
              0, 
              ctx
            );

          if (utils::are_coins_sorted<Y, Z>()) {

            // We sell Coin<Z> -> Coin<Y>
            // In the Pool<Y, Z> we are selling the second token
            let coin_y = swap_token_y(
              v_storage,
              s_storage,
              coin_z, 
              coin_out_min_value, 
              ctx
            );

            // Swap ended 
            (coin::zero<X>(ctx), coin_y)
            } else {

            // We sell Coin<Z> -> Coin<Y>
            // In the Pool<Z, Y> we are selling the first token
            let coin_y = swap_token_x(
              v_storage,
              s_storage,
              coin_z, 
              coin_out_min_value, 
              ctx
            );

            // Swap ended 
            (coin::zero<X>(ctx), coin_y)
            }
           }
        }
    }

/**
* @notice This performa a two hop swap. If Coin<X> has a value of 0, it will follow this path: Y -> B1 -> B2 -> X
* if Coin<Y> has a value of 0, it will follow this path: X -> B1 -> B2 -> Y
* @param v_storage the storage object of the ipx::dex_volatile module
* @param s_storage the storage object of the ipx::dex_stable module 
* @param coin_x if Coin<X> value is zero. The fn will perform this swap Y -> B1 -> B2 -> X 
* @param coin_y if Coin<Y> value is zero. The fn will perform this swap X -> B1 -> B2 -> Y 
* @param coin_out_min_value the minimum final value accepted by the caller 
* @return (Coin<X>, Coin<Y>) the type of the coin sold will have a value of 0
*/
public fun two_hop_swap<X, Y, B1, B2>(
    v_storage: &mut VStorage,
    s_storage: &mut SStorage,
    coin_x: Coin<X>,
    coin_y: Coin<Y>,
    coin_out_min_value: u64,
    ctx: &mut TxContext
  ):(Coin<X>, Coin<Y>) {
    // If Coin<X> has a value of 0
    // We will perform a Y -> B1 -> B2 -> X
    if (coin::value(&coin_x) == 0) {
    
    // Swap function requires the tokens to be sorted
    if (utils::are_coins_sorted<Y, B1>()) {
      // Sell Y -> B1
      let (coin_y, coin_b1) = swap(
        v_storage,
        s_storage,
        coin_y,
        coin::zero<B1>(ctx),
        0,
        ctx
      );
    
     // Sell B1 -> B2 -> X
     let (coin_b1, coin_x) = one_hop_swap<B1, X, B2>(
        v_storage,
        s_storage,
        coin_b1,
        coin_x,
        coin_out_min_value,
        ctx
      );

      coin::destroy_zero(coin_b1);
      (coin_x, coin_y)
    } else {
      // Sell Y -> B1
      let (coin_b1, coin_y) = swap(
        v_storage,
        s_storage,
        coin::zero<B1>(ctx),
        coin_y,
        0,
        ctx
      );

      // Sell B1 -> B2 -> X
      let (coin_b1, coin_x) = one_hop_swap<B1, X, B2>(
        v_storage,
        s_storage,
        coin_b1,
        coin_x,
        coin_out_min_value,
        ctx
      );

      coin::destroy_zero(coin_b1);
      (coin_x, coin_y)
    }  

    // X -> B1 -> B2 -> Y
    } else {
      // Swap function requires the tokens to be sorted
      if (utils::are_coins_sorted<X, B1>()) {
        // Sell X -> B1
        let (coin_x, coin_b1) = swap(
          v_storage,
          s_storage,
          coin_x,
          coin::zero<B1>(ctx),
          0,
          ctx
        );  

       // Sell B1 -> B2 -> Y
       let (coin_b1, coin_y) = one_hop_swap<B1, Y, B2>(
        v_storage,
        s_storage,
        coin_b1,
        coin_y,
        coin_out_min_value,
        ctx
      );

      coin::destroy_zero(coin_b1);
      (coin_x, coin_y)
      } else {
        // Sell X -> B1
        let (coin_b1, coin_x) = swap(
          v_storage,
          s_storage,
          coin::zero<B1>(ctx),
          coin_x,
          0,
          ctx
        );

      // Sell B1 -> B2 -> Y
      let (coin_b1, coin_y) = one_hop_swap<B1, Y, B2>(
        v_storage,
        s_storage,
        coin_b1,
        coin_y,
        coin_out_min_value,
        ctx
      );

      coin::destroy_zero(coin_b1);
      (coin_x, coin_y)
      }
    }
  }

  /**
  * @notice This function calculates the right ratio to add liquidity to prevent loss to the caller and adds liquidity to volatile Pool<X, Y>
  * It will return any extra coin_x sent
  * @param v_storage The storage object of the module ipx::dex_volatile 
  * @param coin_x The Coin<X> of Pool<X, Y>
  * @param coin_y The Coin<Y> of Pool<X, Y>
  * @param vlp_coin_min_amiunt the minimum amount of shares the caller is willing to receive
  * @return the shares equivalent to the deposited token
  */
  public fun add_v_liquidity<X, Y>(
    v_storage: &mut VStorage,
    coin_x: Coin<X>,
    coin_y: Coin<Y>,
    vlp_coin_min_amount: u64,
    ctx: &mut TxContext
  ): (Coin<VLPCoin<X, Y>>) {
    let coin_x_value = coin::value(&coin_x);
    let coin_y_value = coin::value(&coin_y);

    // Get the current pool reserves
    let (coin_x_reserves, coin_y_reserves, _) =  volatile::get_amounts(volatile::borrow_pool<X, Y>(v_storage));

    // Calculate an optimal coinX and coinY amount to keep the pool's ratio
    let (optimal_x_amount, optimal_y_amount) = calculate_optimal_add_liquidity(
        coin_x_value,
        coin_y_value,
        coin_x_reserves,
        coin_y_reserves
    );
    
    // Repay the extra amount
    if (coin_x_value > optimal_x_amount) pay::split_and_transfer(&mut coin_x, coin_x_value - optimal_x_amount, tx_context::sender(ctx), ctx);
    if (coin_y_value > optimal_y_amount) pay::split_and_transfer(&mut coin_y, coin_y_value - optimal_y_amount, tx_context::sender(ctx), ctx);

    // Add liquidity
    volatile::add_liquidity(
        v_storage,
        coin_x,
        coin_y,
        vlp_coin_min_amount,
        ctx
      )
  }

  /**
  * @notice This function calculates the right ratio to add liquidity to prevent loss to the caller and adds liquidity to stable Pool<X, Y>
  * It will return any extra coin_x sent
  * @param s_storage The storage object of the module ipx::dex_stable 
  * @param coin_x The Coin<X> of Pool<X, Y>
  * @param coin_y The Coin<Y> of Pool<X, Y>
  * @param slp_coin_min_amiunt the minimum amount of shares the caller is willing to receive
  * @return the shares equivalent to the deposited token
  */
  public fun add_s_liquidity<X, Y>(
    s_storage: &mut SStorage,
    coin_x: Coin<X>,
    coin_y: Coin<Y>,
    slp_coin_min_amount: u64,
    ctx: &mut TxContext
  ): (Coin<SLPCoin<X, Y>>) {
    let coin_x_value = coin::value(&coin_x);
    let coin_y_value = coin::value(&coin_y);
    
    // Get the current pool reserves
    let (coin_x_reserves, coin_y_reserves, _) =  stable::get_amounts(stable::borrow_pool<X, Y>(s_storage));

    // Calculate an optimal coinX and coinY amount to keep the pool's ratio
    let (optimal_x_amount, optimal_y_amount) = calculate_optimal_add_liquidity(
        coin_x_value,
        coin_y_value,
        coin_x_reserves,
        coin_y_reserves
    );
    
    // Repay the extra amount
    if (coin_x_value > optimal_x_amount) pay::split_and_transfer(&mut coin_x, coin_x_value - optimal_x_amount, tx_context::sender(ctx), ctx);
    if (coin_y_value > optimal_y_amount) pay::split_and_transfer(&mut coin_y, coin_y_value - optimal_y_amount, tx_context::sender(ctx), ctx);

    // Add liquidity
    stable::add_liquidity(
        s_storage,
        coin_x,
        coin_y,
        slp_coin_min_amount,
        ctx
      )
  }

  /**
  * @notice It indicates which pool (stable/volatile) is more profitable for the caller
  * @param v_storage the storage object of the ipx::dex_volatile module
  * @param s_storage the storage object of the ipx::dex_stable module 
  * @param coin_x_value the value of Coin<X> of Pool<X, Y>
  * @param coin_y_value the value Coin<Y> of Pool<X, Y>
  * @return bool true if the volatile pool is more profitable
  * Requirements: 
  * - One of the pools must exist
  */
  public fun is_volatile_better<X, Y>(
    v_storage: &VStorage,
    s_storage: &SStorage,
    coin_x_value: u64,
    coin_y_value: u64
  ): bool {
    // Fetch if pools have been deployed
    let is_stable_deployed = stable::is_pool_deployed<X, Y>(s_storage);
    let is_volatile_deployed = volatile::is_pool_deployed<X, Y>(v_storage);

    // We do not need to do any calculations if one of the pools is not deployed
    // Fetching the price costs a lot of gas on stable pools, we only want to do it when absolutely necessary
    if (is_volatile_deployed && !is_stable_deployed) return true;
    if (is_stable_deployed && !is_volatile_deployed) return false;

    // Throw before doing any further calls to save gas
    assert!(is_stable_deployed && is_volatile_deployed, ERROR_POOL_NOT_DEPLOYED);

    // Fetch the pools
    let v_pool = volatile::borrow_pool<X, Y>(v_storage);
    let s_pool = stable::borrow_pool<X, Y>(s_storage);

    // Get their reserves to calculate the best price
    let (v_reserve_x, v_reserve_y, _) = volatile::get_amounts(v_pool);
    let (s_reserve_x, s_reserve_y, _) = stable::get_amounts(s_pool);

    // If coin_x is 0, we assume the caller is selling Coin<Y> to get Coin<X>
    let v_amount_out = if (coin_x_value == 0) {
      volatile::calculate_value_out(coin_y_value, v_reserve_y, v_reserve_x)
    } else {
      volatile::calculate_value_out(coin_x_value, v_reserve_x, v_reserve_y)
    };

    // If coin_x is 0, we assume the caller is selling Coin<Y> to get Coin<X>
    let s_amount_out = if (coin_x_value == 0) {
      stable::calculate_value_out(s_pool, coin_y_value, s_reserve_x, s_reserve_y, false)
    } else {
      stable::calculate_value_out(s_pool, coin_x_value, s_reserve_x, s_reserve_y, true)
    };

    // Volatile pools consumes less gas and is more profitable for the protocol :) 
    v_amount_out >= s_amount_out
  }
  
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
}