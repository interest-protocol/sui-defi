#[test_only]
module library::utils_tests {
  use std::vector;

  use sui::test_scenario::{Self as test, next_tx, ctx, Scenario};
  use sui::test_utils::{assert_eq};
  use sui::coin::{Coin, mint_for_testing as mint, burn_for_testing as burn};

  use library::utils::{calculate_cumulative_balance, handle_coin_vector};
  use library::test_utils::{people, scenario};

  struct Ether {}

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

      // properly clocks around MAX_U_128
      assert_eq(calculate_cumulative_balance(MAX_U_128 / 2, 2, 2), 1);

      assert_eq(calculate_cumulative_balance(MAX_U_128 / 2, 2716, 2), 1340282366920938463463374607431768210099);

      // does not overflow
      assert_eq(calculate_cumulative_balance(MAX_U_128, 27816, 227326119), 227326119);
    };
    test::end(scenario);  
  }

  fun test_handle_coin_vector_(test: &mut Scenario) {
      let (alice, _) = people();

      let desired_amount = 1000000000;
      next_tx(test, alice);
      {
        let coin_vector = vector::empty<Coin<Ether>>();

        vector::push_back(&mut coin_vector, mint<Ether>(desired_amount, ctx(test)));
        vector::push_back(&mut coin_vector, mint<Ether>(desired_amount, ctx(test)));

        let coin = handle_coin_vector<Ether>(
          coin_vector,
          desired_amount,
          ctx(test)
          );

        assert!(burn(coin) == desired_amount, 0);  
      }
  }

  #[test] 
  fun test_handle_coin_vector() {
    let scenario = scenario();
    test_handle_coin_vector_(&mut scenario);
    test::end(scenario);
  }
}