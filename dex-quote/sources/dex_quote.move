module dex_quote::dex_quote {
  use sui::math;

  use dex::core::{Self, DEXStorage};
  use dex::curve::{Volatile, Stable};
  
  use library::utils;
  use library::math::{mul_div};

  public fun quote_swap_x<X, Y>(
    storage: &DEXStorage,
    amount: u64
    ): u64 {
      quote_swap<X, Y>(storage, amount, 0)
  }

  public fun quote_swap_y<X, Y>(
    storage: &DEXStorage,
    amount: u64
    ): u64 {
      quote_swap<X, Y>(storage, 0, amount)
  }

  public fun quote_one_hop_swap<X, B, Y>(
    storage: &DEXStorage,
    amount: u64
  ): u64 {

    if (utils::are_coins_sorted<X, B>()) {
        let amount_b = quote_swap_x<X, B>(
            storage,
            amount, 
          );

        if (utils::are_coins_sorted<B, Y>()) {
            quote_swap_x<B, Y>(
              storage,
              amount_b
            )
            } else {
            // We sell Coin<Z> -> Coin<Y>
            // In the Pool<Z, Y> we are selling the first token
            quote_swap_y<Y, B>(
              storage,
              amount_b
            )
            }
           } else {
            let amount_b = quote_swap_y<B, X>(
              storage,
              amount
            );

          if (utils::are_coins_sorted<B, Y>()) {

            // We sell Coin<Z> -> Coin<Y>
            // In the Pool<Y, Z> we are selling the second token
            quote_swap_x<B, Y>(
              storage,
              amount_b
            )
            } else {

            // We sell Coin<Z> -> Coin<Y>
            // In the Pool<Z, Y> we are selling the first token
            quote_swap_y<Y, B>(
              storage,
              amount_b
            )
          }
      }
  }

  public fun quote_two_hop_swap<X, B1, B2, Y>(
    storage: &DEXStorage,
    amount: u64
  ): u64 {
    // X -> B1 -> B2 -> Y
      // Swap function requires the tokens to be sorted
      if (utils::are_coins_sorted<X, B1>()) {
        // Sell X -> B1
        let amount_b1 = quote_swap_x<X, B1>(
          storage,
          amount
        );  

        quote_one_hop_swap<B1, B2, Y>(
              storage,
              amount_b1
          )
      } else {
        // Sell X -> B1
        let coin_b1 = quote_swap_y<B1, X>(
          storage,
          amount
        );

        quote_one_hop_swap<B1, B2, Y>(
        storage,
        coin_b1
      )
      }
  }

  public fun quote_add_liquidity<C, X, Y>(
    storage: &DEXStorage,
    amount_x: u64,
    amount_y: u64
  ): (u64, u64, u64) {
    let pool = core::borrow_pool<C, X, Y>(storage);
    let (coin_x_reserve, coin_y_reserve, supply) = core::get_amounts(pool);
    
    let (optimal_x_amount, optimal_y_amount) = calculate_optimal_add_liquidity(
          amount_x,
          amount_y,
          coin_x_reserve,
          coin_y_reserve
    );

    let share_to_mint = math::min(
          mul_div(optimal_x_amount, supply, coin_x_reserve),
          mul_div(optimal_y_amount, supply, coin_y_reserve)
    );

    (share_to_mint, optimal_x_amount, optimal_y_amount)
  }

  public fun quote_remove_liquidity<C, X, Y>(
    storage: &DEXStorage,
    amount: u64
  ): (u64, u64) {
    let pool = core::borrow_pool<C, X, Y>(storage);
    let (coin_x_reserve, coin_y_reserve, supply) = core::get_amounts(pool);
    (
      mul_div(amount, coin_x_reserve, supply),
      mul_div(amount, coin_y_reserve, supply)
    )
  }

  fun quote_swap<X, Y>(
    storage: &DEXStorage,
    coin_x_value: u64,
    coin_y_value: u64
  ): u64 {
    // Fetch if pools have been deployed
    let is_stable_deployed = core::is_pool_deployed<Stable, X, Y>(storage);
    let is_volatile_deployed = core::is_pool_deployed<Volatile, X, Y>(storage);

    // We do not need to do any calculations if one of the pools is not deployed
    // Fetching the price costs a lot of gas on stable pools, we only want to do it when absolutely necessary
    if (is_volatile_deployed && !is_stable_deployed) {
      let v_pool = core::borrow_pool<Volatile, X, Y>(storage);
      let (v_reserve_x, v_reserve_y, _) = core::get_amounts(v_pool);
      
      if (coin_x_value == 0) {
      return core::calculate_v_value_out(coin_y_value, v_reserve_y, v_reserve_x)
      }   else {
      return core::calculate_v_value_out(coin_x_value, v_reserve_x, v_reserve_y)
      }
    };
    if (is_stable_deployed && !is_volatile_deployed) {
        let s_pool = core::borrow_pool<Stable, X, Y>(storage);
        let (s_reserve_x, s_reserve_y, _) = core::get_amounts(s_pool);

        if (coin_x_value == 0) {
        return  core::calculate_s_value_out(s_pool, coin_y_value, s_reserve_x, s_reserve_y, false)
        } else {
        return  core::calculate_s_value_out(s_pool, coin_x_value, s_reserve_x, s_reserve_y, true)
        }
    };

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
    if (v_amount_out >= s_amount_out) { v_amount_out } else { s_amount_out }
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