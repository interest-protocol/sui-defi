module dex::router {

  use sui::coin::{Self, Coin};
  use sui::tx_context::{TxContext};
  use sui::clock::{Clock};
  
  use dex::core::{Self, DEXStorage};
  use dex::curve::{Volatile, Stable};
  
  use library::utils;

  const ERROR_ZERO_VALUE_SWAP: u64 = 1;
  const ERROR_POOL_NOT_DEPLOYED: u64 = 2;

  /**
  * @notice This fun calculates the most profitable pool and calls the fn with the same name on right module
  * It performs a swap: Coin<X> -> Coin<Y> on a Pool<X, Y>
  * @param storage the DEXStorage object of the ipx::dex_volatile module
  * @param clock_object The shared Clock object with id @0x6
  * @param coin_x the Coin<X> the caller intends to sell 
  * @param coin_y_min_value the minimum amount of Coin<Y> the caller is willing to accept 
  * @return Coin<Y> the coin bought
  */
  public fun swap_token_x<X, Y>(
      storage: &mut DEXStorage,
      clock_object: &Clock,
      coin_x: Coin<X>,
      coin_y_min_value: u64,
      ctx: &mut TxContext
      ): Coin<Y> {
      if (is_volatile_better<X, Y>(storage, coin::value(&coin_x), 0)) {
        core::swap_token_x<Volatile, X, Y>(storage,  clock_object, coin_x, coin_y_min_value, ctx)
        } else {
        core::swap_token_x<Stable, X, Y>(storage,  clock_object, coin_x, coin_y_min_value, ctx)
        }
    }

  /**
  * @notice This fun calculates the most profitable pool and calls the fn with the same name on right module
  * It performs a swap: Coin<Y> -> Coin<X> on a Pool<X, Y>
  * @param storage the DEXStorage object of the ipx::dex_volatile module
  * @param clock_object The shared Clock object with id @0x6
  * @param coin_y the Coin<Y> the caller intends to sell 
  * @param coin_x_min_value the minimum amount of Coin<X> the caller is willing to accept 
  * @return Coin<X> the coin bought
  */
  public fun swap_token_y<X, Y>(
      storage: &mut DEXStorage,
      clock_object: &Clock,
      coin_y: Coin<Y>,
      coin_x_min_value: u64,
      ctx: &mut TxContext
      ): Coin<X> {
        if (is_volatile_better<X, Y>(storage, 0, coin::value(&coin_y))) {
          core::swap_token_y<Volatile, X, Y>(storage, clock_object, coin_y, coin_x_min_value, ctx)
          } else {
          core::swap_token_y<Stable, X, Y>(storage, clock_object, coin_y, coin_x_min_value, ctx)
          }
    }

  /**
  * @notice It performs a swap between two Pools. E.g., ETH -> BTC -> SUI (BTC/ETH) <> (BTC/SUI)
  * @param storage the DEXStorage object of the ipx::dex_volatile module
  * @param clock_object The shared Clock object with id @0x6
  * @param coin_x if Coin<X> value is zero. The fn will perform this swap X -> B -> Y
  * @param coin_out_min_value the minimum final value accepted by the caller 
  * @return (Coin<X>, Coin<Y>) the type of the coin sold will have a value of 0
  */
   // X -> B -> Y
  public fun one_hop_swap<X, B, Y>(
    storage: &mut DEXStorage,
    clock_object: &Clock,
    coin_x: Coin<X>,
    coin_out_min_value: u64,
    ctx: &mut TxContext
  ): Coin<Y> {

    // One of the coins must have a value greater than zero or we are wasting gas
    assert!(coin::value(&coin_x) != 0, ERROR_ZERO_VALUE_SWAP);

    if (utils::are_coins_sorted<X, B>()) {
        let coin_b = swap_token_x<X, B>(
            storage,
            clock_object,
            coin_x, 
            0, 
            ctx
          );

        if (utils::are_coins_sorted<B, Y>()) {
            let coin_y = swap_token_x(
              storage,
              clock_object,
              coin_b, 
              coin_out_min_value, 
              ctx
            );

            // Swap ended
            coin_y
            
            } else {
            // We sell Coin<Z> -> Coin<Y>
            // In the Pool<Z, Y> we are selling the first token
            let coin_y = swap_token_y(
              storage,
              clock_object,
              coin_b, 
              coin_out_min_value, 
              ctx
            );

             // Swap ended 
             coin_y
            }
           } else {
            let coin_b = swap_token_y<B, X>(
              storage,
              clock_object,
              coin_x, 
              0, 
              ctx
            );

          if (utils::are_coins_sorted<B, Y>()) {

            // We sell Coin<Z> -> Coin<Y>
            // In the Pool<Y, Z> we are selling the second token
            let coin_y = swap_token_x(
              storage,
              clock_object,
              coin_b, 
              coin_out_min_value, 
              ctx
            );

            // Swap ended 
            coin_y
            } else {

            // We sell Coin<Z> -> Coin<Y>
            // In the Pool<Z, Y> we are selling the first token
            let coin_y = swap_token_y(
              storage,
              clock_object,
              coin_b, 
              coin_out_min_value, 
              ctx
            );

            // Swap ended 
            coin_y
            }
           }
    }


  /**
  * @notice It performs a swap between three Pools. E.g., ETH -> BTC -> SUI -> DAI
  * @param storage the DEXStorage object of the ipx::dex_volatile module
  * @param clock_object The shared Clock object with id @0x6
  * @param coin_x if Coin<X> value is zero. The fn will perform this swap X -> B1 -> B2 -> Y
  * @param coin_out_min_value the minimum final value accepted by the caller 
  * @return (Coin<X>, Coin<Y>) the type of the coin sold will have a value of 0
  */
  // X -> B1 -> B2 -> Y
public fun two_hop_swap<X, B1, B2, Y>(
    storage: &mut DEXStorage,
    clock_object: &Clock,
    coin_x: Coin<X>,
    coin_out_min_value: u64,
    ctx: &mut TxContext
  ): Coin<Y> {
    // X -> B1 -> B2 -> Y
      // Swap function requires the tokens to be sorted
      if (utils::are_coins_sorted<X, B1>()) {
        // Sell X -> B1
        let coin_b1 = swap_token_x<X, B1>(
          storage,
          clock_object,
          coin_x,
          0,
          ctx
        );  

        one_hop_swap<B1, B2, Y>(
              storage,
              clock_object,
              coin_b1,
              coin_out_min_value, ctx
          )
      } else {
        // Sell X -> B1
        let coin_b1 = swap_token_y<B1, X>(
          storage,
          clock_object,
          coin_x,
          0,
          ctx
        );

        one_hop_swap<B1, B2, Y>(
        storage,
        clock_object,
        coin_b1,
        coin_out_min_value,
        ctx
      )
      }
  }

  /**
  * @notice It indicates which pool (stable/volatile) is more profitable for the caller
  * @param The DEXStorage shared object of the DEX module
  * @param coin_x_value the value of Coin<X> of Pool<X, Y>
  * @param coin_y_value the value Coin<Y> of Pool<X, Y>
  * @return bool true if the volatile pool is more profitable
  * Requirements: 
  * - One of the pools must exist
  */
  public fun is_volatile_better<X, Y>(
    storage: &DEXStorage,
    coin_x_value: u64,
    coin_y_value: u64
  ): bool {
    // Fetch if pools have been deployed
    let is_stable_deployed = core::is_pool_deployed<Stable, X, Y>(storage);
    let is_volatile_deployed = core::is_pool_deployed<Volatile, X, Y>(storage);

    // We do not need to do any calculations if one of the pools is not deployed
    // Fetching the price costs a lot of gas on stable pools, we only want to do it when absolutely necessary
    if (is_volatile_deployed && !is_stable_deployed) return true;
    if (is_stable_deployed && !is_volatile_deployed) return false;

    // Throw before doing any further calls to save gas
    assert!(is_stable_deployed && is_volatile_deployed, ERROR_POOL_NOT_DEPLOYED);

    // Fetch the pools
    let v_pool = core::borrow_pool<Volatile, X, Y>(storage);
    let s_pool = core::borrow_pool<Stable, X, Y>(storage);

    // Get their reserves to calculate the best price
    let (v_reserve_x, v_reserve_y, _) = core::get_amounts(v_pool);
    let (s_reserve_x, s_reserve_y, _) = core::get_amounts(s_pool);

    // If coin_x is 0, we assume the caller is selling Coin<Y> to get Coin<X>
    let v_amount_out = if (coin_x_value == 0) {
      core::calculate_v_value_out(coin_y_value, v_reserve_y, v_reserve_x)
    } else {
      core::calculate_v_value_out(coin_x_value, v_reserve_x, v_reserve_y)
    };

    // If coin_x is 0, we assume the caller is selling Coin<Y> to get Coin<X>
    let s_amount_out = if (coin_x_value == 0) {
      core::calculate_s_value_out(s_pool, coin_y_value, s_reserve_x, s_reserve_y, false)
    } else {
      core::calculate_s_value_out(s_pool, coin_x_value, s_reserve_x, s_reserve_y, true)
    };

    // Volatile pools consumes less gas and is more profitable for the protocol :) 
    v_amount_out >= s_amount_out
  }
}