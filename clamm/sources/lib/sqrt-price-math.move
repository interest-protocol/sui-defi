// Based on https://github.com/Uniswap/v3-core/blob/main/contracts/libraries/SqrtPriceMath.sol
// We reduce the precision of the sqrt Q96 to Q64 to avoid overflow errors. We do not have access to the mulDiv by https://xn--2-umb.com/21/muldiv/
// It is important to note that Sui tokens have 9 decimals as the default 18 decimals of solidity so sqrt of price Q96 will never be as large as in Ethereu, Therefore the loss of precision if minimal
module clamm::sqrt_price_math {

  use clamm::math_u256::{mul_div, mul_div_round_up, div_round_up};

  const Q64: u256 = 0xFFFFFFFFFFFFFFFF;

  // Errors
  const ERROR_INVALID_PRICE: u64 = 0;

  public fun calc_amount_x_delta(
    sqrt_price_a_q96: u256, 
    sqrt_price_b_q96: u256, 
    liquidity: u128, 
    round_up: bool
  ): u256 {

    let safe_price_a = sqrt_price_a_q96 >> 32;
    let safe_price_b = sqrt_price_b_q96 >> 32;

    let (lower_price, higher_price) = if (safe_price_a > safe_price_b) (safe_price_b, safe_price_a) else (safe_price_a, safe_price_b);

    assert!(lower_price != 0, ERROR_INVALID_PRICE);

    let numerator_1 = (liquidity as u256) << 64;
    let numerator_2 = higher_price - lower_price;

    if (round_up) div_round_up(
      mul_div_round_up(numerator_1, numerator_2, higher_price),
      lower_price
      ) else
      mul_div(numerator_1, numerator_2, higher_price) / lower_price
  }

  public fun calc_amount_y_delta(
    sqrt_price_a_q96: u256, 
    sqrt_price_b_q96: u256, 
    liquidity: u128, 
    round_up: bool
  ): u256 {

    let safe_price_a = sqrt_price_a_q96 >> 32;
    let safe_price_b = sqrt_price_b_q96 >> 32;

    let (lower_price, higher_price) = if (safe_price_a > safe_price_b) (safe_price_b, safe_price_a) else (safe_price_a, safe_price_b);

    let numerator_1 = (liquidity as u256) << 64;

    if (round_up) mul_div_round_up(numerator_1, higher_price -  lower_price, Q64) else
      mul_div(numerator_1, higher_price -  lower_price, Q64)
  }

}