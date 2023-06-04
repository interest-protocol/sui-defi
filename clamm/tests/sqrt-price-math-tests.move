#[test_only]
module clamm::sqrt_price_math_tests {

  use sui::test_utils::{assert_eq};

  use clamm::sqrt_price_math ::{calc_amount_x_delta, calc_amount_y_delta};

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
}