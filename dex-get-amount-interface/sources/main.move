module dex_get_amount_interface::dex_get_amount_interface {

  use dex::core::{Self, DEXStorage};
  use dex::curve::{Volatile, Stable};
  
  use library::utils;

   public fun get_swap_token_x_amount_out<X, Y>(
      storage: &DEXStorage,
      amount: u64
      ): u64 {
      get_best_amount<X, Y>(storage, amount, 0)
  }

  public fun get_swap_token_y_amount_out<X, Y>(
      storage: &DEXStorage,
      amount: u64
      ): u64 {
      get_best_amount<X, Y>(storage, 0, amount)
  }

  public fun get_one_hop_swap_amount_out<X, B, Y>(
    storage: &DEXStorage,
    amount: u64
  ): u64 {

    if (utils::are_coins_sorted<X, B>()) {
        let amount_b = get_swap_token_x_amount_out<X, B>(
            storage,
            amount, 
          );

        if (utils::are_coins_sorted<B, Y>()) {
            get_swap_token_x_amount_out<B, Y>(
              storage,
              amount_b
            )
            } else {
            // We sell Coin<Z> -> Coin<Y>
            // In the Pool<Z, Y> we are selling the first token
            get_swap_token_y_amount_out<Y, B>(
              storage,
              amount_b
            )
            }
           } else {
            let amount_b = get_swap_token_y_amount_out<B, X>(
              storage,
              amount
            );

          if (utils::are_coins_sorted<B, Y>()) {

            // We sell Coin<Z> -> Coin<Y>
            // In the Pool<Y, Z> we are selling the second token
            get_swap_token_x_amount_out<B, Y>(
              storage,
              amount_b
            )
            } else {

            // We sell Coin<Z> -> Coin<Y>
            // In the Pool<Z, Y> we are selling the first token
            get_swap_token_y_amount_out<Y, B>(
              storage,
              amount_b
            )
          }
      }
  }

  public fun get_two_hop_swap_amount_out<X, B1, B2, Y>(
    storage: &DEXStorage,
    amount: u64
  ): u64 {
    // X -> B1 -> B2 -> Y
      // Swap function requires the tokens to be sorted
      if (utils::are_coins_sorted<X, B1>()) {
        // Sell X -> B1
        let amount_b1 = get_swap_token_x_amount_out<X, B1>(
          storage,
          amount
        );  

        get_one_hop_swap_amount_out<B1, B2, Y>(
              storage,
              amount_b1
          )
      } else {
        // Sell X -> B1
        let coin_b1 = get_swap_token_y_amount_out<B1, X>(
          storage,
          amount
        );

        get_one_hop_swap_amount_out<B1, B2, Y>(
        storage,
        coin_b1
      )
      }
  }

  public fun get_best_amount<X, Y>(
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
}