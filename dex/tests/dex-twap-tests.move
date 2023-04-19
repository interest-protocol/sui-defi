#[test_only]
module dex::dex_twap_tests {
  use std::vector;

  use sui::coin::{mint_for_testing as mint, burn_for_testing as burn};
  use sui::test_scenario::{Self as test, next_tx, Scenario, ctx};
  use sui::test_utils::{assert_eq};
  use sui::clock;

  use dex::core::{Self as dex, DEXStorage as Storage};
  use dex::curve::{Volatile};
  use library::test_utils::{people, scenario};
  use library::eth::{ETH};
  use library::usdc::{USDC};
  use library::utils::{calculate_cumulative_balance};

  // 1 ETH => 1500 USDC
  const INITIAL_ETHER_VALUE: u64 = 100000;
  const INITIAL_USDC_VALUE: u64 = 150000000;
  const ZERO_ACCOUNT: address = @0x0;
  const START_TIME_STAMP: u64 = 1234;

  #[test]
  fun test_initial_state() {
    let scenario = scenario();

    let test = &mut scenario;

    let (alice, _) = people();

    start_dex(test);

    next_tx(test, alice);
    {
      let storage = test::take_shared<Storage>(test);

      let observations_vector = dex::get_observations<Volatile, ETH, USDC>(&storage);

      let (balance_x_cumulative_last, balance_y_cumulative_last) = dex::get_pool_cumulative_balances_last<Volatile, ETH, USDC>(&storage);

      assert_eq(vector::length(observations_vector), dex::get_granularity());
      assert_eq(balance_x_cumulative_last, calculate_cumulative_balance((INITIAL_ETHER_VALUE as u256), START_TIME_STAMP, 0));
      assert_eq(balance_y_cumulative_last, calculate_cumulative_balance((INITIAL_USDC_VALUE as u256), START_TIME_STAMP, 0));

      test::return_shared(storage);            
    };  

    test::end(scenario);
  }

  #[test]
  fun test_get_coin_price() {
    let scenario = scenario();

    let test = &mut scenario;

    let (alice, _) = people();

    start_dex(test);
    let clock_object = clock::create_for_testing(ctx(test));
    clock::increment_for_testing(&mut clock_object, START_TIME_STAMP);
    
    next_tx(test, alice);
    {
      let storage = test::take_shared<Storage>(test);

      let period_size = dex::get_period_size();

      burn(dex::swap_token_y<Volatile, ETH, USDC>(
        &mut storage,
        &clock_object,
        mint<USDC>(2000000, ctx(test)),
        0,
        ctx(test)
      ));

      clock::increment_for_testing(&mut clock_object, period_size);
      burn(dex::swap_token_y<Volatile, ETH, USDC>(
        &mut storage,
        &clock_object,
        mint<USDC>(2000000, ctx(test)),
        0,
        ctx(test)
      ));

      clock::increment_for_testing(&mut clock_object, period_size);
      burn(dex::swap_token_y<Volatile, ETH, USDC>(
        &mut storage,
        &clock_object,
        mint<USDC>(2000000, ctx(test)),
        0,
        ctx(test)
      ));

      clock::increment_for_testing(&mut clock_object, period_size);
      burn(dex::swap_token_y<Volatile, ETH, USDC>(
        &mut storage,
        &clock_object,
        mint<USDC>(2000000, ctx(test)),
        0,
        ctx(test)
      ));

      clock::increment_for_testing(&mut clock_object, period_size);
      burn(dex::swap_token_y<Volatile, ETH, USDC>(
        &mut storage,
        &clock_object,
        mint<USDC>(2000000, ctx(test)),
        0,
        ctx(test)
      ));

      let (eth_reserves, usdc_reserves, _) = dex::get_pool_info<Volatile, ETH, USDC>(&storage);
      let eth_twap_price = dex::get_coin_x_price<Volatile, ETH, USDC>(&mut storage, &clock_object, 1);
      let usdc_twap_price = dex::get_coin_y_price<Volatile, ETH, USDC>(&mut storage, &clock_object, 20000);

      assert_eq(eth_twap_price < usdc_reserves / eth_reserves, true);
      assert_eq(eth_twap_price > 1500, true);

      assert_eq(usdc_twap_price, 11);
    
      test::return_shared(storage);            
    };

    clock::destroy_for_testing(clock_object);
    test::end(scenario);       
  }

  fun start_dex(test: &mut Scenario) {
    let (alice, _) = people();
    
    next_tx(test, alice);
    {
      dex::init_for_testing(ctx(test));
    };
    
    let clock_object = clock::create_for_testing(ctx(test));
    next_tx(test, alice);
    {
      let storage = test::take_shared<Storage>(test);

      clock::increment_for_testing(&mut clock_object, START_TIME_STAMP);

      burn(dex::create_v_pool(
        &mut storage,
        &clock_object,
        mint<ETH>(INITIAL_ETHER_VALUE, ctx(test)),
        mint<USDC>(INITIAL_USDC_VALUE, ctx(test)),
        ctx(test)
      ));
       
      test::return_shared(storage);
    };

    clock::destroy_for_testing(clock_object);
  }
}