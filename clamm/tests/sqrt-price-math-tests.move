#[test_only]
module clamm::sqrt_price_math_tests {

  use sui::test_utils::{assert_eq};

  use clamm::sqrt_price_math::{calc_amount_x_delta, calc_amount_y_delta, get_next_sqrt_price_from_input, get_next_sqrt_price_from_amount_x_round_up, get_next_sqrt_price_from_output};

  const MAX_U256: u256 = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;


  #[test]
  fun test_calc_amount_x_delta() {
    assert_eq(calc_amount_x_delta(79228162514264337593543950336, 112045541949572279837463876454, 0, true), 0);
    assert_eq(calc_amount_x_delta(79228162514264337593543950336, 79228162514264337593543950336, 0, true), 0);
    assert_eq(calc_amount_x_delta(79228162514264337593543950336, 87150978765690771352898345369, 1000000000000000000, true), 90909090909090910);
    assert_eq(calc_amount_x_delta(79228162514264337593543950336, 87150978765690771352898345369, 1000000000000000000, false), 90909090909090910 - 1);

    let amount_up = calc_amount_x_delta(2787593149816327892691964784081045188247552, 22300745198530623141535718272648361505980416, 1000000000000000000, true);
    let amount_down = calc_amount_x_delta(2787593149816327892691964784081045188247552, 22300745198530623141535718272648361505980416, 1000000000000000000, false);
    assert_eq(amount_up, 24869);
    assert_eq(amount_up, amount_down + 1);
  }

  #[test]
  fun test_calc_amount_y_delta() {
    assert_eq(calc_amount_y_delta(79228162514264337593543950336, 112045541949572279837463876454, 0, true), 0);
    assert_eq(calc_amount_y_delta(79228162514264337593543950336, 79228162514264337593543950336, 0, true), 0);
    
    let amount_up = calc_amount_y_delta(0x01000000000000000000000000, 0x01199999999999999999999999, 0x0de0b6b3a7640000, true);
    let amount_down = calc_amount_y_delta(0x01000000000000000000000000, 0x01199999999999999999999999, 0x0de0b6b3a7640000, false);
    assert_eq(amount_up, 100000000000000000);
    assert_eq(amount_up - 1, amount_down);
  }

  #[test]
  #[expected_failure(abort_code = clamm::sqrt_price_math::ERROR_INVALID_PRICE)]
  fun test_get_next_sqrt_price_from_input_error_zero_price() {
    // fails if price is zero
    get_next_sqrt_price_from_input(0, 0, 1000000000, false);
  }

  #[test]
  #[expected_failure(abort_code = clamm::sqrt_price_math::ERROR_INVALID_LIQUIDITY)]
  fun test_get_next_sqrt_price_from_input_error_zero_liquidity() {
    // fails if liquidity is zero
    get_next_sqrt_price_from_input(1, 0, 1000000000, false);
  }

  #[test]
  #[expected_failure(abort_code = clamm::sqrt_price_math::ERROR_PRICE_OVERFLOW)]
  fun test_get_next_sqrt_price_from_input_error_price_overflows() {
    get_next_sqrt_price_from_input(0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF, 1024, 1024, false);
  }

  #[test]
  #[expected_failure(abort_code = clamm::sqrt_price_math::ERROR_INVALID_PRICE)]
  fun test_get_next_sqrt_price_from_input_error_price_overflows_2() {
    // fails if input amount overflows the price
    assert_eq(get_next_sqrt_price_from_amount_x_round_up(1, 1, 0x8000000000000000000000000000000000000000000000000000000000000000, false), 1);
  }


  #[test]
  fun test_get_next_sqrt_price_from_input() {
    // returns input price if amount in is zero and zeroForOne = true
    assert_eq(get_next_sqrt_price_from_input(0x01000000000000000000000000, 100000000, 0, true), 0x01000000000000000000000000);

    // returns input price if amount in is zero and zeroForOne = false
    assert_eq(get_next_sqrt_price_from_input(0x01000000000000000000000000, 100000000, 0, false), 0x01000000000000000000000000);

    // input amount of 0.1 token1
    assert_eq(get_next_sqrt_price_from_input(0x01000000000000000000000000, 1000000000, 100000000, false), 87150978765690771352898345369);

    // input amount of 0.1 token0
    assert_eq(get_next_sqrt_price_from_input(0x01000000000000000000000000, 1000000000, 100000000, true), 72025602285694852359719485440);

    // amountIn > type(uint96).max and zeroForOne = true
    assert_eq(get_next_sqrt_price_from_amount_x_round_up(0x01000000000000000000000000, 0x8ac7230489e80000, 0x10000000000000000000000000, true), 625000003076620288);

    // can return 1 with enough amountIn and zeroForOne = true
    assert_eq(get_next_sqrt_price_from_amount_x_round_up(0x01000000000000000000000000, 1, 0x7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff, true), 1);
    
    // returns the minimum price for max inputs
    assert_eq(get_next_sqrt_price_from_amount_x_round_up(0xffffffffffffffffffffffffffffffffffffffff, 0xffffffffffffffffffffffffffffffff, 0xffffffffffffffffffffffffffffffffffffffffffffffff0000000000000000, true), 1);

    // any input amount cannot underflow the price
    assert_eq(get_next_sqrt_price_from_amount_x_round_up(1, 1, 0x8000000000000000000000000000000000000000000000000000000000000000, true), 1);
  }

  #[test]
  #[expected_failure(abort_code = clamm::sqrt_price_math::ERROR_INVALID_PRICE)]
  fun test_get_next_sqrt_price_from_output_error_zero_price() {
    // fails if price is zero
    get_next_sqrt_price_from_output(0, 0, 1000000000, false);
  }

  #[test]
  #[expected_failure(abort_code = clamm::sqrt_price_math::ERROR_INVALID_LIQUIDITY)]
  fun test_get_next_sqrt_price_from_output_error_zero_liquidity() {
    // fails if liquidity is zero
    get_next_sqrt_price_from_output(1, 0, 1000000000, true);
  }

  #[test]
  #[expected_failure(abort_code = clamm::sqrt_price_math::ERROR_INVALID_LOW_LIQUIDITY)]
  fun test_get_next_sqrt_price_from_output_error_low_liquidity() {
    // fails if output amount is exactly the virtual reserves of token0
    // puzzling echidna test
    get_next_sqrt_price_from_output(20282409603651670423947251286016, 1024, 4, false);
  }

  #[test]
  #[expected_failure(abort_code = clamm::sqrt_price_math::ERROR_INVALID_LOW_LIQUIDITY)]
  fun test_get_next_sqrt_price_from_output_error_low_liquidity_2() {
    // fails if output amount is greater than virtual reserves of token0
    get_next_sqrt_price_from_output(20282409603651670423947251286016, 1024, 5, false);
  }

  #[test]
  #[expected_failure(abort_code = clamm::sqrt_price_math::ERROR_INVALID_PRICE)]
  fun test_get_next_sqrt_price_from_output_error_invalid_price_2() {
    // fails if output amount is greater than virtual reserves of token1
    get_next_sqrt_price_from_output(20282409603651670423947251286016, 1024, 262145, true);
  }

  #[test]
  #[expected_failure]
  fun test_get_next_sqrt_price_from_output_error_high_amount() {
    // reverts if amountOut is impossible in zero for one direction
    // Impossible to swap the max U256
    get_next_sqrt_price_from_output(0x01000000000000000000000000, 1, MAX_U256, true);
  }

  #[test]
  #[expected_failure]
  fun test_get_next_sqrt_price_from_output_error_high_amount_2() {
    // reverts if amountOut is impossible in zero for one direction
    // Impossible to swap the max U256
    get_next_sqrt_price_from_output(0x01000000000000000000000000, 1, MAX_U256, false);
  }

  #[test]
  fun test_get_next_sqrt_price_from_output() {
    // succeeds if output amount is just less than the virtual reserves of token1
    assert_eq(get_next_sqrt_price_from_output(20282409603651670423947251286016, 1024, 262143, true), 77371252455337362397855744);

    // returns input price if amount in is zero and zeroForOne = true
    assert_eq(get_next_sqrt_price_from_output(0x01000000000000000000000000, 100000000000000000, 0, true), 0x01000000000000000000000000);
    
    // returns input price if amount in is zero and zeroForOne = false
    assert_eq(get_next_sqrt_price_from_output(0x01000000000000000000000000, 100000000000000000, 0, false), 0x01000000000000000000000000);

    // output amount of 0.1 token0
    assert_eq(get_next_sqrt_price_from_output(0x01000000000000000000000000, 1000000000000000000, 100000000000000000, false), 88031291682515930660447715328);

    // output amount of 0.1 token1
    assert_eq(get_next_sqrt_price_from_output(0x01000000000000000000000000, 1000000000000000000, 100000000000000000, true), 71305346262837903832471568384);
  }

}
