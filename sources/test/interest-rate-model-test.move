#[test_only]
module interest_protocol::interest_rate_model_test {

  use sui::test_scenario::{Self as test, Scenario, next_tx, ctx};

  use interest_protocol::interest_rate_model::{Self as model, InterestRateModelStorage};
  use interest_protocol::test_utils::{people, scenario};
  use interest_protocol::utils::{get_coin_info_string};
  use interest_protocol::math::{d_fdiv, d_fmul_u256, double_scalar};

  const ONE_PERCENT: u256 = 10000000000000000;
  const TWO_PERCENT: u256 = 20000000000000000;
  const KINK: u256 = 700000000000000000; // 70%
  const MS_PER_YEAR: u256 = 31536000000; 
  
  struct BTC {}

  fun init_test(test: &mut Scenario) {
    let (alice, _) = people();

    next_tx(test, alice);
    {
      model::init_for_testing(ctx(test));
    };

    next_tx(test, alice);
    {
      let storage = test::take_shared<InterestRateModelStorage>(test);

      model::set_interest_rate_data_test<BTC>(
        &mut storage,
        ONE_PERCENT, // base 
        TWO_PERCENT + ONE_PERCENT, // multiplier
        TWO_PERCENT * 3,
        KINK,
        ctx(test)
      );
      test::return_shared(storage);
    };

    next_tx(test, alice);
    {
      let storage = test::take_shared<InterestRateModelStorage>(test);
      let (base_rate_per_ms, multiplier_rate_per_ms, jump_rate_per_ms, kink) = model::get_interest_rate_data<BTC>(&storage);

      assert!(base_rate_per_ms == ONE_PERCENT / MS_PER_YEAR, 0);
      assert!(multiplier_rate_per_ms == (TWO_PERCENT + ONE_PERCENT) / MS_PER_YEAR, 0);
      assert!(jump_rate_per_ms == (TWO_PERCENT * 3) / MS_PER_YEAR, 0);
      assert!(kink == KINK, 0);
      test::return_shared(storage);
    };
  }

  fun test_get_borrow_rate_per_ms_(test: &mut Scenario) {
    init_test(test);

    let (alice, _) = people();

    
    next_tx(test, alice);
    {
      let cash = 20000000000000000; // 20M
      let reserves = 5000000000000000; // 5M
      let total_borrows = 60000000000000000; // 60m
      let storage = test::take_shared<InterestRateModelStorage>(test);

      let borrow_rate_per_ms = model::get_borrow_rate_per_ms(
        &mut storage,
        get_coin_info_string<BTC>(),
        cash,
        total_borrows,
        reserves
      );

      // Above kink - 80%
      let utilization_rate = d_fdiv(total_borrows, (total_borrows + cash - reserves));

      let (base_rate_per_ms, multiplier_rate_per_ms, jump_rate_per_ms, kink) = model::get_interest_rate_data<BTC>(&storage);

      assert!(utilization_rate > kink, 0);
      assert!(utilization_rate == 800000000000000000, 0);

      let expected_rate = d_fmul_u256(kink, multiplier_rate_per_ms) + base_rate_per_ms;
      let excess =  utilization_rate - kink;
      let expected_rate = expected_rate + d_fmul_u256(excess, jump_rate_per_ms);

      assert!(borrow_rate_per_ms == (expected_rate as u64), 0);
      // 0.037%
      // sanity check
      assert!(expected_rate * MS_PER_YEAR == 36999927360000000, 0);

      test::return_shared(storage);
    };

     next_tx(test, alice);
    {
      let cash = 60000000000000000; // 60M
      let reserves = 5000000000000000; // 5M
      let total_borrows = 10000000000000000; // 10m
      let storage = test::take_shared<InterestRateModelStorage>(test);

      let borrow_rate_per_ms = model::get_borrow_rate_per_ms(
        &mut storage,
        get_coin_info_string<BTC>(),
        cash,
        total_borrows,
        reserves
      );

      // 15% or so
      let utilization_rate = d_fdiv(total_borrows, (total_borrows + cash - reserves));

      let (base_rate_per_ms, multiplier_rate_per_ms, _, kink) = model::get_interest_rate_data<BTC>(&storage);

      assert!(utilization_rate < kink, 0);

      let expected_rate = d_fmul_u256(utilization_rate, multiplier_rate_per_ms) + base_rate_per_ms;

      assert!(borrow_rate_per_ms == (expected_rate as u64), 0);
      // sanity check
      assert!(expected_rate * MS_PER_YEAR == 14615327664000000, 0);
    
      test::return_shared(storage);
    };
  }

  #[test]
  fun test_get_borrow_rate_per_ms() {
    let scenario = scenario();
    test_get_borrow_rate_per_ms_(&mut scenario);
    test::end(scenario);
  }

  fun test_get_supply_rate_per_epoch_(test: &mut Scenario) {
     init_test(test);

    let (alice, _) = people();

    
    next_tx(test, alice);
    {
      let cash = 20000000000000000; // 20M
      let reserves = 5000000000000000; // 5M
      let total_borrows = 60000000000000000; // 60m
      let reserve_factor = 200000000000000000; // 20%
      let storage = test::take_shared<InterestRateModelStorage>(test);

      let supply_rate_per_ms = model::get_supply_rate_per_ms(
        &mut storage,
        get_coin_info_string<BTC>(),
        cash,
        total_borrows,
        reserves,
        reserve_factor
      );

      // Above kink 80%
      let utilization_rate = d_fdiv(total_borrows, (total_borrows + cash - reserves));

      let (base_rate_per_ms, multiplier_rate_per_ms, jump_rate_per_ms, kink) = model::get_interest_rate_data<BTC>(&storage);

      assert!(utilization_rate > kink, 0);

      let expected_rate = d_fmul_u256(kink, multiplier_rate_per_ms) + base_rate_per_ms;
      let excess =  utilization_rate - KINK;
      let expected_rate = d_fmul_u256(expected_rate + d_fmul_u256(excess, jump_rate_per_ms), double_scalar() - reserve_factor);
      let expected_rate = d_fmul_u256(utilization_rate, expected_rate);

      assert!(supply_rate_per_ms == (expected_rate as u64), 0);
      assert!(expected_rate * MS_PER_YEAR == 23679940896000000, 0);
    
      test::return_shared(storage);
    };


     next_tx(test, alice);
    {
      let cash = 60000000000000000; // 60M
      let reserves = 5000000000000000; // 5M
      let total_borrows = 10000000000000000; // 10m
      let reserve_factor = 150000000000000000;
      let storage = test::take_shared<InterestRateModelStorage>(test);

      let supply_rate_per_ms = model::get_supply_rate_per_ms(
        &mut storage,
        get_coin_info_string<BTC>(),
        cash,
        total_borrows,
        reserves,
        reserve_factor
      );

      // Below kink
      let utilization_rate = d_fdiv(total_borrows, (total_borrows + cash - reserves));

      let (base_rate_per_ms, multiplier_rate_per_ms, _, kink) = model::get_interest_rate_data<BTC>(&storage);
      assert!(utilization_rate < kink, 0);

      let expected_rate = d_fmul_u256(d_fmul_u256(utilization_rate, multiplier_rate_per_ms) + base_rate_per_ms, double_scalar() - reserve_factor);
      let expected_rate = d_fmul_u256(expected_rate, utilization_rate);

      assert!(supply_rate_per_ms == (expected_rate as u64), 0);
      assert!(expected_rate * MS_PER_YEAR == 1911207744000000, 0);

      test::return_shared(storage);
    };
  }

  #[test]
  fun test_get_supply_rate_per_epoch() {
    let scenario = scenario();
    test_get_supply_rate_per_epoch_(&mut scenario);
    test::end(scenario);
  }
}