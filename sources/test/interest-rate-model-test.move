module interest_protocol::interest_rate_model_test {

  // use sui::test_scenario::{Self as test, Scenario, next_tx, ctx};

  // use interest_protocol::interest_rate_model::{Self as model, InterestRateModelStorage};
  // use interest_protocol::test_utils::{people, scenario};
  // use interest_protocol::utils::{get_coin_info, get_epochs_per_year};
  // use interest_protocol::math::{fmul, fdiv, one};

  // const ONE_PERCENT: u64 = 10000000;
  // const TWO_PERCENT: u64 = 20000000;
  // const THREE_PERCENT: u64 = 30000000;
  // const KINK: u64 = 700000000; // 70%

  // struct BTC {}

  // fun init_test(test: &mut Scenario) {
  //   let (alice, _) = people();

  //   next_tx(test, alice);
  //   {
  //     model::init_for_testing(ctx(test));
  //   };

  //   next_tx(test, alice);
  //   {
  //     let storage = test::take_shared<InterestRateModelStorage>(test);
  //     model::set_interest_rate_data_test<BTC>(
  //       &mut storage,
  //       ONE_PERCENT, // base 
  //       TWO_PERCENT + ONE_PERCENT, // multiplier
  //       THREE_PERCENT * 3,
  //       KINK,
  //       ctx(test)
  //     );
  //     test::return_shared(storage);
  //   };

  //   next_tx(test, alice);
  //   {
  //     let storage = test::take_shared<InterestRateModelStorage>(test);
  //     let (base_rate_per_epoch, multiplier_rate_per_epoch, jump_rate_per_epoch, kink) = model::get_interest_rate_data<BTC>(&storage);

  //     let epochs_per_year = get_epochs_per_year();

  //     assert!(base_rate_per_epoch == ONE_PERCENT / epochs_per_year, 0);
  //     assert!(multiplier_rate_per_epoch == THREE_PERCENT / epochs_per_year, 0);
  //     assert!(jump_rate_per_epoch == (THREE_PERCENT * 3) / epochs_per_year, 0);
  //     assert!(kink == KINK, 0);
  //     test::return_shared(storage);
  //   };
  // }

  // fun test_get_borrow_rate_per_epoch_(test: &mut Scenario) {
  //   init_test(test);

  //   let (alice, _) = people();

    
  //   next_tx(test, alice);
  //   {
  //     let cash = 20000000000000000; // 20M
  //     let reserves = 5000000000000000; // 5M
  //     let total_borrows = 60000000000000000; // 60m
  //     let storage = test::take_shared<InterestRateModelStorage>(test);

  //     let borrow_rate_per_epoch = model::get_borrow_rate_per_epoch(
  //       &mut storage,
  //       get_coin_info<BTC>(),
  //       cash,
  //       total_borrows,
  //       reserves
  //     );

  //     // Above kink
  //     let utilization_rate = fdiv(total_borrows, (total_borrows + cash - reserves));

  //     let epochs_per_year = get_epochs_per_year();

  //     let base_rate_per_epoch = ONE_PERCENT / epochs_per_year;
  //     let multiplier_rate_per_epoch = THREE_PERCENT / epochs_per_year;
  //     let jump_rate_per_epoch = (THREE_PERCENT * 3) / epochs_per_year;

  //     assert!(utilization_rate > KINK, 0);

  //     let expected_rate = fmul(KINK, multiplier_rate_per_epoch) + base_rate_per_epoch;
  //     let excess =  utilization_rate - KINK;
  //     let expected_rate = expected_rate + fmul(excess, jump_rate_per_epoch);

  //     assert!(borrow_rate_per_epoch == expected_rate, 0);
    
  //     test::return_shared(storage);
  //   };

  //    next_tx(test, alice);
  //   {
  //     let cash = 60000000000000000; // 60M
  //     let reserves = 5000000000000000; // 5M
  //     let total_borrows = 10000000000000000; // 10m
  //     let storage = test::take_shared<InterestRateModelStorage>(test);

  //     let borrow_rate_per_epoch = model::get_borrow_rate_per_epoch(
  //       &mut storage,
  //       get_coin_info<BTC>(),
  //       cash,
  //       total_borrows,
  //       reserves
  //     );

  //     // Below kink
  //     let utilization_rate = fdiv(total_borrows, (total_borrows + cash - reserves));

  //     let epochs_per_year = get_epochs_per_year();

  //     let base_rate_per_epoch = ONE_PERCENT / epochs_per_year;
  //     let multiplier_rate_per_epoch = THREE_PERCENT / epochs_per_year;

  //     assert!(utilization_rate < KINK, 0);

  //     let expected_rate = fmul(utilization_rate, multiplier_rate_per_epoch) + base_rate_per_epoch;

  //     assert!(borrow_rate_per_epoch == expected_rate, 0);
    
  //     test::return_shared(storage);
  //   };
  // }

  // #[test]
  // fun test_get_borrow_rate_per_epoch() {
  //   let scenario = scenario();
  //   test_get_borrow_rate_per_epoch_(&mut scenario);
  //   test::end(scenario);
  // }

  // fun test_get_supply_rate_per_epoch_(test: &mut Scenario) {
  //    init_test(test);

  //   let (alice, _) = people();

    
  //   next_tx(test, alice);
  //   {
  //     let cash = 20000000000000000; // 20M
  //     let reserves = 5000000000000000; // 5M
  //     let total_borrows = 60000000000000000; // 60m
  //     let reserve_factor = 200000000;
  //     let storage = test::take_shared<InterestRateModelStorage>(test);

  //     let borrow_rate_per_epoch = model::get_supply_rate_per_epoch(
  //       &mut storage,
  //       get_coin_info<BTC>(),
  //       cash,
  //       total_borrows,
  //       reserves,
  //       reserve_factor
  //     );

  //     // Above kink
  //     let utilization_rate = fdiv(total_borrows, (total_borrows + cash - reserves));

  //     let epochs_per_year = get_epochs_per_year();

  //     let base_rate_per_epoch = ONE_PERCENT / epochs_per_year;
  //     let multiplier_rate_per_epoch = THREE_PERCENT / epochs_per_year;
  //     let jump_rate_per_epoch = (THREE_PERCENT * 3) / epochs_per_year;

  //     assert!(utilization_rate > KINK, 0);

  //     let expected_rate = fmul(KINK, multiplier_rate_per_epoch) + base_rate_per_epoch;
  //     let excess =  utilization_rate - KINK;
  //     let expected_rate = fmul(expected_rate + fmul(excess, jump_rate_per_epoch), (one() as u64) - reserve_factor);
  //     let expected_rate = fmul(utilization_rate, expected_rate);

  //     assert!(borrow_rate_per_epoch == expected_rate, 0);
    
  //     test::return_shared(storage);
  //   };


  //    next_tx(test, alice);
  //   {
  //     let cash = 60000000000000000; // 60M
  //     let reserves = 5000000000000000; // 5M
  //     let total_borrows = 10000000000000000; // 10m
  //     let reserve_factor = 150000000;
  //     let storage = test::take_shared<InterestRateModelStorage>(test);

  //     let borrow_rate_per_epoch = model::get_supply_rate_per_epoch(
  //       &mut storage,
  //       get_coin_info<BTC>(),
  //       cash,
  //       total_borrows,
  //       reserves,
  //       reserve_factor
  //     );

  //     // Below kink
  //     let utilization_rate = fdiv(total_borrows, (total_borrows + cash - reserves));

  //     let epochs_per_year = get_epochs_per_year();

  //     let base_rate_per_epoch = ONE_PERCENT / epochs_per_year;
  //     let multiplier_rate_per_epoch = THREE_PERCENT / epochs_per_year;

  //     assert!(utilization_rate < KINK, 0);

  //     let expected_rate = fmul(fmul(utilization_rate, multiplier_rate_per_epoch) + base_rate_per_epoch, (one() as u64) - reserve_factor);
  //     let expected_rate = fmul(expected_rate, utilization_rate);

  //     assert!(borrow_rate_per_epoch == expected_rate, 0);
    
  //     test::return_shared(storage);
  //   };
  // }

  // #[test]
  // fun test_get_supply_rate_per_epoch() {
  //   let scenario = scenario();
  //   test_get_supply_rate_per_epoch_(&mut scenario);
  //   test::end(scenario);
  // }
}