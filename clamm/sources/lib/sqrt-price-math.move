// Based on https://github.com/Uniswap/v3-core/blob/main/contracts/libraries/SqrtPriceMath.sol
// We reduce the precision of the sqrt Q96 to Q64 to avoid overflow errors. We do not have access to the mulDiv by https://xn--2-umb.com/21/muldiv/
// It is important to note that Sui tokens have 9 decimals as the default 18 decimals of solidity so sqrt of price Q96 will never be as large as in Ethereu, Therefore the loss of precision if minimal
module clamm::sqrt_price_math {

  use clamm::math_u256::{mul_div, mul_div_round_up, div_round_up};

  const Q64: u256 = 0xFFFFFFFFFFFFFFFF;
  const MAX_U160: u256 = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
  const MAX_U256: u256 = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;

  // Errors
  const ERROR_INVALID_PRICE: u64 = 0;
  const ERROR_INVALID_LIQUIDITY: u64 = 3;
  const ERROR_PRICE_OVERFLOW: u64 = 4;
  const ERROR_INVALID_LOW_LIQUIDITY: u64 = 5;


  fun will_overflow(x: u256, y: u256):bool {
    (MAX_U256 / y) < x
  }

  fun assert_u160(x: u256): u256 {
    assert!(MAX_U160 >= x, ERROR_PRICE_OVERFLOW);
    x
  }

  public fun get_next_sqrt_price_from_amount_x_round_up(
    sqrt_price_q96: u256,
    liquidity: u256,
    amount: u256,
    add: bool
  ): u256 {
    if (amount == 0) return sqrt_price_q96;

    if (add) {

      let (numerator_1_q64, price_q64, numerator_1_q96) = (
        liquidity << 64,
        sqrt_price_q96 >> 32,
        liquidity << 96
      );

      // price_q64 can underflow to 0
      if (price_q64 != 0 && !will_overflow(amount, price_q64)) {
        
        let product = amount * price_q64;
        let denominator = numerator_1_q64 + product;
        
        if (denominator >= numerator_1_q64) {
          return mul_div_round_up(numerator_1_q64, price_q64, denominator) << 32
        }
      };

      // If the price is 0, it will throw here
      return (div_round_up(numerator_1_q96, ((numerator_1_q96 / sqrt_price_q96) + amount)))
    } else {

    let (numerator_1, price) = (
      liquidity << 64,
      sqrt_price_q96 >> 32
      );

      assert!(price != 0 && !will_overflow(amount, price), ERROR_INVALID_PRICE);

      let product = amount * price;
      
      assert!(numerator_1 > product, ERROR_INVALID_LOW_LIQUIDITY);
      
      let denominator = numerator_1 - product;
      mul_div_round_up(numerator_1, price, denominator) << 32
    }
  } 

  public fun get_next_sqrt_price_from_amount_y_round_down(
    sqrt_price_q96: u256,
    liquidity: u256,
    amount: u256,
    add: bool
  ): u256 {
    
    if (add) {
      if (MAX_U160 >= amount) {
        ((amount << 96) / liquidity) + sqrt_price_q96
      } else {
        (mul_div(amount, Q64, liquidity) + (sqrt_price_q96 >> 32)) << 32
      }
    } else {
      let quotient = mul_div_round_up(amount, Q64, liquidity);
      let safe_price = sqrt_price_q96 >> 32;
      assert!(safe_price > quotient, ERROR_INVALID_PRICE);

      (safe_price - quotient) << 32
    }
  }

  public fun get_next_sqrt_price_from_input(
    sqrt_price_q96: u256,
    liquidity: u128,
    amount: u256,
    sell_x_to_y: bool
  ): u256 {
    assert!(sqrt_price_q96 != 0, ERROR_INVALID_PRICE);
    assert!(liquidity != 0, ERROR_INVALID_LIQUIDITY);

    if (sell_x_to_y) { 
      assert_u160(get_next_sqrt_price_from_amount_x_round_up(sqrt_price_q96, (liquidity as u256), amount, true)) 
      } else {
      assert_u160(get_next_sqrt_price_from_amount_y_round_down(sqrt_price_q96, (liquidity as u256), amount, true))
      }
  }

  public fun get_next_sqrt_price_from_output(
    sqrt_price_q96: u256,
    liquidity: u128,
    amount: u256,
    sell_x_to_y: bool
  ): u256 {
    assert!(sqrt_price_q96 != 0, ERROR_INVALID_PRICE);
    assert!(liquidity != 0, ERROR_INVALID_LIQUIDITY);

    if (sell_x_to_y) {
      assert_u160(get_next_sqrt_price_from_amount_y_round_down(sqrt_price_q96, (liquidity as u256), amount, false))
    } else {
      assert_u160(get_next_sqrt_price_from_amount_x_round_up(sqrt_price_q96, (liquidity as u256), amount, false)) 
    }
  }

  public fun calc_amount_x_delta(
    sqrt_price_a_q96: u256, 
    sqrt_price_b_q96: u256, 
    liquidity: u128, 
    round_up: bool
  ): u256 {

    let safe_price_a = sqrt_price_a_q96 >> 32;
    let safe_price_b = sqrt_price_b_q96 >> 32;

    let (lower_price, higher_price) = if (safe_price_a > safe_price_b) (safe_price_b, safe_price_a) else (safe_price_a, safe_price_b);

    // Check here for underflow because of the shr 32
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

    // Price of 0 will return a 0 amount, so we do not cae about underflows
    if (round_up) mul_div_round_up((liquidity as u256), higher_price -  lower_price, Q64) else
      mul_div((liquidity as u256), higher_price - lower_price, Q64)
  }

}