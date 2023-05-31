#[test_only]
module clamm::ipx_pool_tests {

  use sui::coin::{mint_for_testing as mint, burn_for_testing as burn};
  use sui::test_scenario::{Self, Scenario, next_tx, ctx};
  use sui::test_utils::{assert_eq};
  
  use clamm::ipx_pool::{Self as pool, Storage};
  use clamm::test_utils::{people, scenario, create_sqrt_price};
  
  use i256::i256;

  struct ETH {}

  struct USDC {}

  const INITIAL_ETH_AMOUNT: u64 = 998976618;
  const INITIAL_USDC_AMOUNT: u64 = 5000000000000;

  fun create_pool(test: &mut Scenario) {
     let (alice, _) = people();

     next_tx(test, alice);
     {
      pool::init_for_testing(ctx(test));
     };

     next_tx(test, alice);
     {
     let storage = test_scenario::take_shared<Storage>(test);
      pool::create_pool<ETH, USDC>(&mut storage, create_sqrt_price(5000), 85176, false, ctx(test));
      test_scenario::return_shared(storage);
     };
  }

  #[test]
  fun test_add_liquidity() {
    let scenario = scenario();
    let test = &mut scenario;

    let (alice, _) = people();

    create_pool(test);

    next_tx(test, alice);
    {
      let storage = test_scenario::take_shared<Storage>(test);

      let lower_tick = 84222;
      let upper_tick = 86129;
      let initial_liquidity = 1517882343751509868544;

      pool::add_liquidity<ETH, USDC>(
        &mut storage,
        mint<ETH>(INITIAL_ETH_AMOUNT, ctx(test)),
        mint<USDC>(INITIAL_USDC_AMOUNT, ctx(test)),
        initial_liquidity,
        84222,
        false,
        86129,
        false,
        ctx(test)
      );

      let (balance_x, balance_y, pool_liquidity, raw_current_tick, is_current_tick_neg, current_sqrt_price) = pool::get_pool_info<ETH, USDC>(&storage);

      assert_eq(balance_x, INITIAL_ETH_AMOUNT);
      assert_eq(balance_y, INITIAL_USDC_AMOUNT);
      assert_eq(pool_liquidity, initial_liquidity);
      assert_eq(raw_current_tick, 85176);
      assert_eq(is_current_tick_neg, false);
      assert_eq(current_sqrt_price, create_sqrt_price(5000));

      let alice_position_key = pool::get_user_position_key(alice, &i256::from(lower_tick), &i256::from(upper_tick));
      let alice_position_liquidity = pool::get_user_position_liquidity<ETH, USDC>(&storage, alice_position_key);

      assert_eq(initial_liquidity, alice_position_liquidity);

      let (initialized, liquidity) = pool::get_tick_info<ETH, USDC>(&storage, i256::from(lower_tick));
      assert_eq(initialized, true);
      assert_eq(liquidity, initial_liquidity);

      let (initialized, liquidity) = pool::get_tick_info<ETH, USDC>(&storage, i256::from(upper_tick));
      assert_eq(initialized, true);
      assert_eq(liquidity, initial_liquidity);

      test_scenario::return_shared(storage);
    };



    test_scenario::end(scenario);
  }

    #[test]
  fun test_swap() {
    let scenario = scenario();
    let test = &mut scenario;

    let (alice, _) = people();

    create_pool(test);

    next_tx(test, alice);
    {
      let storage = test_scenario::take_shared<Storage>(test);

      let initial_liquidity = 1517882343751509868544;

      pool::add_liquidity<ETH, USDC>(
        &mut storage,
        mint<ETH>(INITIAL_ETH_AMOUNT, ctx(test)),
        mint<USDC>(INITIAL_USDC_AMOUNT, ctx(test)),
        initial_liquidity,
        84222,
        false,
        86129,
        false,
        ctx(test)
      );

      test_scenario::return_shared(storage);
    };

    next_tx(test, alice);
    {
      let storage = test_scenario::take_shared<Storage>(test);

      assert_eq(burn(pool::swap_y<ETH, USDC>(
        &mut storage,
        mint<USDC>(42000000000, ctx(test)),
        ctx(test)
      )), 8396714);

      let (balance_x, balance_y, pool_liquidity, raw_current_tick, is_current_tick_neg, current_sqrt_price) = pool::get_pool_info<ETH, USDC>(&storage);

      assert_eq(balance_x, INITIAL_ETH_AMOUNT - 8396714);
      assert_eq(balance_y, INITIAL_USDC_AMOUNT + 42000000000);
      assert_eq(current_sqrt_price, 5604469350942327889444743441197);
      assert_eq(raw_current_tick, 85184);
      assert_eq(is_current_tick_neg, false);
      assert_eq(pool_liquidity, 1517882343751509868544);

      test_scenario::return_shared(storage);
    };

    test_scenario::end(scenario);
  }
}

