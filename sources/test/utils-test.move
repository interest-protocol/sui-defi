#[test_only]
module interest_protocol::utils_tests {

  use sui::test_scenario::{Self as test, next_tx};
  use sui::test_utils::{assert_eq};

  use interest_protocol::utils::{calculate_cumulative_balance};
  use interest_protocol::test_utils::{people, scenario};

  const MAX_U_128: u256 = 1340282366920938463463374607431768211455;

  #[test]
  fun test_calculate_cumulative_balance() {

    let scenario = scenario();

    let test = &mut scenario;

    let (alice, _) = people();

    next_tx(test, alice);
    {
      let x = 28172373839;
      let y = 383711;
      let z = 89273619;
      assert_eq(calculate_cumulative_balance(x, y, z), ( x * (y as u256) + z));

      assert_eq(calculate_cumulative_balance(MAX_U_128 / 2, 2, 2), 1);

      assert_eq(calculate_cumulative_balance(MAX_U_128 / 2, 2716, 2), 1340282366920938463463374607431768210099);

      // does not overflow
      assert_eq(calculate_cumulative_balance(MAX_U_128, 27816, 227326119), 227326119);
    };
    test::end(scenario);  
  }


}