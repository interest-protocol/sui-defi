module interest_protocol::router {

  use sui::coin::{Self, Coin};
  use sui::tx_context::{Self, TxContext};
  use sui::clock::{Clock};
  use sui::pay;
  
  use interest_protocol::dex::{Self, Storage, LPCoin};
  use interest_protocol::curve::{Volatile, Stable};
  use interest_protocol::utils;

  const ERROR_ZERO_VALUE_SWAP: u64 = 1;
  const ERROR_POOL_NOT_DEPLOYED: u64 = 2;

  /**
  * @notice This fun calculates the most profitable pool and calls the fn with the same name on right module
  * It performs a swap: Coin<X> -> Coin<Y> on a Pool<X, Y>
  * @param storage the storage object of the ipx::dex_volatile module
  * @param clock_object The shared Clock object with id @0x6
  * @param coin_x the Coin<X> the caller intends to sell 
  * @param coin_y_min_value the minimum amount of Coin<Y> the caller is willing to accept 
  * @return Coin<Y> the coin bought
  */
  fun swap_token_x<X, Y>(
      storage: &mut Storage,
      clock_object: &Clock,
      coin_x: Coin<X>,
      coin_y_min_value: u64,
      ctx: &mut TxContext
      ): Coin<Y> {
      if (is_volatile_better<X, Y>(storage, coin::value(&coin_x), 0)) {
        dex::swap_token_x<Volatile, X, Y>(storage,  clock_object, coin_x, coin_y_min_value, ctx)
        } else {
        dex::swap_token_x<Stable, X, Y>(storage,  clock_object, coin_x, coin_y_min_value, ctx)
        }
    }

  /**
  * @notice This fun calculates the most profitable pool and calls the fn with the same name on right module
  * It performs a swap: Coin<Y> -> Coin<X> on a Pool<X, Y>
  * @param storage the storage object of the ipx::dex_volatile module
  * @param clock_object The shared Clock object with id @0x6
  * @param coin_y the Coin<Y> the caller intends to sell 
  * @param coin_x_min_value the minimum amount of Coin<X> the caller is willing to accept 
  * @return Coin<X> the coin bought
  */
  fun swap_token_y<X, Y>(
      storage: &mut Storage,
      clock_object: &Clock,
      coin_y: Coin<Y>,
      coin_x_min_value: u64,
      ctx: &mut TxContext
      ): Coin<X> {
        if (is_volatile_better<X, Y>(storage, 0, coin::value(&coin_y))) {
          dex::swap_token_y<Volatile, X, Y>(storage, clock_object, coin_y, coin_x_min_value, ctx)
          } else {
          dex::swap_token_y<Stable, X, Y>(storage, clock_object, coin_y, coin_x_min_value, ctx)
          }
    }

  /**
  * @dev This is a helper function to simplify the code. One of the coin values should be 0. 
  * If coin_x value is 0, it will swap Y -> X and vice versa.
  * @param storage the storage object of the ipx::dex_volatile module
  * @param clock_object The shared Clock object with id @0x6
  * @param coin_x the Coin<X> of Pool<X, Y>
  * @param coin_x the Coin<Y> of Pool<X, Y>
  * @param coin_out_min_value the minimum amount of coin the caller is willing to accept 
  * @return (Coin<X>, Coin<Y>) One of the coins will have a value of 0. The one with the same type that was sold.
  */  
  public fun swap<X, Y>(
    storage: &mut Storage,
    clock_object: &Clock,
    coin_x: Coin<X>,
    coin_y: Coin<Y>,
    coin_out_min_value: u64,
    ctx: &mut TxContext
  ): (Coin<X>, Coin<Y>) {
    // If Coin<X> has a value of 0 do a Y -> X swap
    if (coin::value(&coin_x) == 0) {
      coin::destroy_zero(coin_x);
      (swap_token_y(
        storage,
        clock_object,
        coin_y,
        coin_out_min_value,
        ctx
      ), coin::zero<Y>(ctx)) 
    } else {
      coin::destroy_zero(coin_y);
      // If Coin<X> value is not 0 do a Y -> X swap
      (coin::zero<X>(ctx), swap_token_x(
        storage,
        clock_object,
        coin_x,
        coin_out_min_value,
        ctx
      ))
    }
  }  

  /**
  * @notice It performs a swap between two Pools. E.g., ETH -> BTC -> SUI (BTC/ETH) <> (BTC/SUI)
  * @param storage the storage object of the ipx::dex_volatile module
  * @param clock_object The shared Clock object with id @0x6
  * @param coin_x if Coin<X> value is zero. The fn will perform this swap Y -> Z -> X 
  * @param coin_y if Coin<Y> value is zero. The fn will perform this swap X -> Z -> Y
  * @param coin_out_min_value the minimum final value accepted by the caller 
  * @return (Coin<X>, Coin<Y>) the type of the coin sold will have a value of 0
  */
  public fun one_hop_swap<X, Y, Z>(
    storage: &mut Storage,
    clock_object: &Clock,
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
             storage,
             clock_object,
             coin_y, 
             0, 
             ctx
            );

          // We need to sort X/Z to find the pool
          if (utils::are_coins_sorted<X, Z>()) {
            // We sell Coin<X> to buy Coin<X>
            // Assuming the Pool<X,Z>, we are selling the second
            let coin_x = swap_token_y(
              storage,
              clock_object,
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
              storage,
              clock_object,
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
              storage,
              clock_object,
              coin_y, 
              0, 
              ctx
            );

          if (utils::are_coins_sorted<X, Z>()) {
            // We sell Coin<Z> to buy Coin<X>
            // Assuming Pool<X, Z> we are selling the second token
            let coin_x = swap_token_y(
              storage,
              clock_object,
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
              storage,
              clock_object,
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
              storage,
              clock_object,
              coin_x, 
              0, 
              ctx
            );

          if (utils::are_coins_sorted<Y, Z>()) {
            // We sell Coin<Z> -> Coin<Y>
            // In the Pool<Y, Z> we are selling the second token
            let coin_y = swap_token_y(
              storage,
              clock_object,
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
              storage,
              clock_object,
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
              storage,
              clock_object,
              coin_x, 
              0, 
              ctx
            );

          if (utils::are_coins_sorted<Y, Z>()) {

            // We sell Coin<Z> -> Coin<Y>
            // In the Pool<Y, Z> we are selling the second token
            let coin_y = swap_token_y(
              storage,
              clock_object,
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
              storage,
              clock_object,
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
* @param storage the storage object of the ipx::dex_volatile module
* @param clock_object The shared
* @param coin_x if Coin<X> value is zero. The fn will perform this swap Y -> B1 -> B2 -> X 
* @param coin_y if Coin<Y> value is zero. The fn will perform this swap X -> B1 -> B2 -> Y 
* @param coin_out_min_value the minimum final value accepted by the caller 
* @return (Coin<X>, Coin<Y>) the type of the coin sold will have a value of 0
*/
public fun two_hop_swap<X, Y, B1, B2>(
    storage: &mut Storage,
    clock_object: &Clock,
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
        storage,
        clock_object,
        coin_y,
        coin::zero<B1>(ctx),
        0,
        ctx
      );
    
     // Sell B1 -> B2 -> X
     let (coin_b1, coin_x) = one_hop_swap<B1, X, B2>(
        storage,
        clock_object,
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
        storage,
        clock_object,
        coin::zero<B1>(ctx),
        coin_y,
        0,
        ctx
      );

      // Sell B1 -> B2 -> X
      let (coin_b1, coin_x) = one_hop_swap<B1, X, B2>(
        storage,
        clock_object,
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
          storage,
          clock_object,
          coin_x,
          coin::zero<B1>(ctx),
          0,
          ctx
        );  

       // Sell B1 -> B2 -> Y
       let (coin_b1, coin_y) = one_hop_swap<B1, Y, B2>(
        storage,
        clock_object,
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
          storage,
          clock_object,
          coin::zero<B1>(ctx),
          coin_x,
          0,
          ctx
        );

      // Sell B1 -> B2 -> Y
      let (coin_b1, coin_y) = one_hop_swap<B1, Y, B2>(
        storage,
        clock_object,
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
  * @param storage The storage object of the module ipx::dex_volatile 
  * @param clock_object The shared Clock object with id @0x6
  * @param coin_x The Coin<X> of Pool<X, Y>
  * @param coin_y The Coin<Y> of Pool<X, Y>
  * @param vlp_coin_min_amiunt the minimum amount of shares the caller is willing to receive
  * @return the shares equivalent to the deposited token
  */
  public fun add_liquidity<C, X, Y>(
    storage: &mut Storage,
    clock_object: &Clock,
    coin_x: Coin<X>,
    coin_y: Coin<Y>,
    vlp_coin_min_amount: u64,
    ctx: &mut TxContext
  ): (Coin<LPCoin<C, X, Y>>) {
    let coin_x_value = coin::value(&coin_x);
    let coin_y_value = coin::value(&coin_y);

    // Get the current pool reserves
    let (coin_x_reserves, coin_y_reserves, _) =  dex::get_amounts(dex::borrow_pool<C, X, Y>(storage));

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
    dex::add_liquidity(
        storage,
        clock_object,
        coin_x,
        coin_y,
        vlp_coin_min_amount,
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
    storage: &Storage,
    coin_x_value: u64,
    coin_y_value: u64
  ): bool {
    // Fetch if pools have been deployed
    let is_stable_deployed = dex::is_pool_deployed<Stable, X, Y>(storage);
    let is_volatile_deployed = dex::is_pool_deployed<Volatile, X, Y>(storage);

    // We do not need to do any calculations if one of the pools is not deployed
    // Fetching the price costs a lot of gas on stable pools, we only want to do it when absolutely necessary
    if (is_volatile_deployed && !is_stable_deployed) return true;
    if (is_stable_deployed && !is_volatile_deployed) return false;

    // Throw before doing any further calls to save gas
    assert!(is_stable_deployed && is_volatile_deployed, ERROR_POOL_NOT_DEPLOYED);

    // Fetch the pools
    let v_pool = dex::borrow_pool<Volatile, X, Y>(storage);
    let s_pool = dex::borrow_pool<Stable, X, Y>(storage);

    // Get their reserves to calculate the best price
    let (v_reserve_x, v_reserve_y, _) = dex::get_amounts(v_pool);
    let (s_reserve_x, s_reserve_y, _) = dex::get_amounts(s_pool);

    // If coin_x is 0, we assume the caller is selling Coin<Y> to get Coin<X>
    let v_amount_out = if (coin_x_value == 0) {
      dex::calculate_v_value_out(coin_y_value, v_reserve_y, v_reserve_x)
    } else {
      dex::calculate_v_value_out(coin_x_value, v_reserve_x, v_reserve_y)
    };

    // If coin_x is 0, we assume the caller is selling Coin<Y> to get Coin<X>
    let s_amount_out = if (coin_x_value == 0) {
      dex::calculate_s_value_out(s_pool, coin_y_value, s_reserve_x, s_reserve_y, false)
    } else {
      dex::calculate_s_value_out(s_pool, coin_x_value, s_reserve_x, s_reserve_y, true)
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