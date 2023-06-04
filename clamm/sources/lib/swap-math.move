module clamm::swap_math {

  use clamm::sqrt_price_math::{calc_amount_x_delta, calc_amount_y_delta, get_next_sqrt_price_from_input};

  public fun compute_swap_step(
    sqrt_price_current_q96: u256,
    sqrt_price_target_q96: u256,
    liquidity: u128,
    amount_remaining: u256
  ): (u256, u256, u256) {
    
    // If the current price is going down, we are selling X to Buy Y
    // It is because we track the X price in function of Y in the contract
    let sell_x_to_y = sqrt_price_current_q96 >= sqrt_price_target_q96;

    let next_sqrt_price_q96 = get_next_sqrt_price_from_input(
      sqrt_price_current_q96,
      liquidity,
      amount_remaining,
      sell_x_to_y
    );

    let amount_in = calc_amount_x_delta(sqrt_price_current_q96, next_sqrt_price_q96, liquidity, sell_x_to_y );

    let amount_out = calc_amount_y_delta(sqrt_price_current_q96, next_sqrt_price_q96, liquidity, sell_x_to_y);

    if (sell_x_to_y) (next_sqrt_price_q96, amount_in, amount_out) else (next_sqrt_price_q96, amount_out, amount_in)
  }
}