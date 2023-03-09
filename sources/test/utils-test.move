#[test_only]
module interest_protocol::utils_tests {
  use std::vector;

  use sui::test_scenario::{Self as test, Scenario, next_tx, ctx};
  use sui::coin::{Coin, mint_for_testing as mint, destroy_for_testing as burn};

  use interest_protocol::utils;
  use interest_protocol::test_utils::{people, scenario};
  
  struct Ether {}

  fun test_handle_coin_vector_(test: &mut Scenario) {
      let (alice, _) = people();

      let desired_amount = 1000000000;
      next_tx(test, alice);
      {
        let coin_vector = vector::empty<Coin<Ether>>();

        vector::push_back(&mut coin_vector, mint<Ether>(desired_amount, ctx(test)));
        vector::push_back(&mut coin_vector, mint<Ether>(desired_amount, ctx(test)));

        let coin = utils::handle_coin_vector<Ether>(
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