#[test_only]
module clamm::bit_math_tests {
  use sui::test_utils::{assert_eq};

  use clamm::bit_math::{most_significant_bit, least_significant_bit};
  use clamm::test_utils::{pow};

  const MAX_U256: u256 = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;


  #[test]
  fun test_most_significant_bit() {
    assert_eq(most_significant_bit(1), 0);
    assert_eq(most_significant_bit(2), 1);
    assert_eq(most_significant_bit(MAX_U256), 255);

    let index: u16 = 0;

    while (index <= 255) {
      assert_eq(most_significant_bit((pow(2, (index as u8)) as u256)), (index as u8));
      index = index + 1;
    }
  }

  #[test]
  fun test_least_significant_bit() {
    assert_eq(least_significant_bit(1), 0);
    assert_eq(least_significant_bit(2), 1);
    assert_eq(least_significant_bit(MAX_U256), 0);

    let index: u16 = 0;

    while (index <= 255) {
      assert_eq(least_significant_bit((pow(2, (index as u8)) as u256)), (index as u8));
      index = index + 1;
    }
  }

  #[test]
  #[expected_failure(abort_code = clamm::bit_math::ERROR_INVALID_VALUE)]
  fun test_error_most_significant_bit() {
    assert_eq(most_significant_bit(0), 0);
  }

  #[test]
  #[expected_failure(abort_code = clamm::bit_math::ERROR_INVALID_VALUE)]
  fun test_error_least_significant_bit() {
    assert_eq(least_significant_bit(0), 0);
  }
}