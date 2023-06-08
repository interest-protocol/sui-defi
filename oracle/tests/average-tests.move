#[test_only]
module oracle::average_tests {

  use sui::test_utils::{assert_eq};

  use oracle::ipx_oracle::{get_safe_average as average};

  #[test]
  #[expected_failure(abort_code = oracle::ipx_oracle::ERROR_BAD_PRICES)]
  fun throws_if_diff_is_above_threshold() {
    assert_eq(average(5, 6), 5);
  }

  #[test]
  #[expected_failure(abort_code = oracle::ipx_oracle::ERROR_BAD_PRICES)]
  fun throws_if_diff_is_above_threshold_2() {
    assert_eq(average(6, 5), 5);
  }

  #[test]
  #[expected_failure(abort_code = oracle::ipx_oracle::ERROR_BAD_PRICES)]
  fun throws_if_diff_is_above_threshold_3() {
    assert_eq(average(97, 100), 5);
  }

  #[test]
  #[expected_failure(abort_code = oracle::ipx_oracle::ERROR_BAD_PRICES)]
  fun throws_if_diff_is_above_threshold_4() {
    assert_eq(average(970000000000000000000, 1000000000000000000000), 5);
  }

  #[test]
  fun returns_average() {
    assert_eq(average(3, 3), 3);
    assert_eq(average(3, 3), 3);
    assert_eq(average(970000000000000000000, 970000000000000000000), 970000000000000000000);
    assert_eq(average(98, 100), 99);
    assert_eq(average(980000000000000000000, 1000000000000000000000), 990000000000000000000);
    assert_eq(average(60, 59), 59);
  }

}