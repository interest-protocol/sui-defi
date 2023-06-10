#[test_only]
module library::utils_tests {
  use std::vector;

  use sui::test_scenario::{Self as test, next_tx, ctx, Scenario};
  use sui::coin::{Coin, mint_for_testing as mint, burn_for_testing as burn};

  use library::utils::{handle_coin_vector};
  use library::test_utils::{people, scenario};

  struct Ether {}

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