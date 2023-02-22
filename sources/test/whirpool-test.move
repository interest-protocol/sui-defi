#[test_only]
module interest_protocol::whirpool_test {

  use sui::test_scenario::{Self as test, Scenario, next_tx, ctx};
  use sui::test_utils::{assert_eq};
  use sui::coin::{destroy_for_testing as burn};
  use sui::math;

  use interest_protocol::whirpool::{Self, WhirpoolAdminCap, WhirpoolStorage, AccountStorage};
  use interest_protocol::ipx::{Self, IPXStorage};
  use interest_protocol::dnr::{Self, DineroStorage};
  use interest_protocol::oracle::{Self, OracleStorage, OracleAdminCap};
  use interest_protocol::interest_rate_model::{Self as model, InterestRateModelStorage};
  use interest_protocol::math::{fmul};
  use interest_protocol::test_utils::{people, scenario, mint, advance_epoch};

  const ONE_PERCENT: u64 = 10000000;
  const TWO_PERCENT: u64 = 20000000;
  const THREE_PERCENT: u64 = 30000000;
  const KINK: u64 = 700000000; // 70%
  const INITIAL_BTC_PRICE: u64 = 200000000000; // 20k - 7 decimals
  const INITIAL_ETH_PRICE: u64 = 140000000000; // 1400 - 8 decimals
  const INITIAL_ADA_PRICE: u64 = 300000000; // 30 cents - 9 decimals
  const BTC_BORROW_CAP: u64 = 100000000000; // 100 BTC - 9 decimals
  const ETH_BORROW_CAP: u64 = 50000000000; // 500 ETH 8 decimals
  const ADA_BORROW_CAP: u64 = 1000000000000; // 100k 7 decimals
  const BTC_DECIMALS: u8 = 9;
  const ETH_DECIMALS: u8 = 8;
  const ADA_DECIMALS: u8 = 7;
  const IPX_DECIMALS_FACTOR: u256 = 1000000000;
  const BTC_DECIMALS_FACTOR: u256 = 1000000000;
  const ETH_DECIMALS_FACTOR: u256 = 100000000;
  const ADA_DECIMALS_FACTOR: u256 = 10000000;

  struct BTC {}
  struct ETH {}
  struct ADA {}

  fun init_test(test: &mut Scenario) {
    let (alice, _) = people();

    // Init modules
    next_tx(test, alice);
    {
      whirpool::init_for_testing(ctx(test));
      ipx::init_for_testing(ctx(test));
      dnr::init_for_testing(ctx(test));
      model::init_for_testing(ctx(test));
      oracle::init_for_testing(ctx(test));
    };

    // BTC/ETH/ADA Interest Rate
    next_tx(test, alice);
    {
      let storage = test::take_shared<InterestRateModelStorage>(test);

      // BTC
      model::set_interest_rate_data_test<BTC>(
        &mut storage,
        ONE_PERCENT, // base 
        TWO_PERCENT, // multiplier
        THREE_PERCENT, // jump
        KINK,
        ctx(test)
      );

      // ETH
      model::set_interest_rate_data_test<ETH>(
        &mut storage,
        ONE_PERCENT * 2, // base 
        TWO_PERCENT, // multiplier
        THREE_PERCENT * 2, // jump
        KINK,
        ctx(test)
      );

       // ADA
      model::set_interest_rate_data_test<ADA>(
        &mut storage,
        ONE_PERCENT, // base 
        THREE_PERCENT, // multiplier
        THREE_PERCENT * 3, // jump
        KINK,
        ctx(test)
      );
      test::return_shared(storage);
    };

    // Oracle
    next_tx(test, alice);
    {
      let oracle_admin_cap = test::take_from_address<OracleAdminCap>(test, alice);
      let oracle_storage = test::take_shared<OracleStorage>(test);

      // BTC
      oracle::set_price<BTC>(
        &oracle_admin_cap,
        &mut oracle_storage,
        INITIAL_BTC_PRICE,
        7,
        ctx(test)
      );

      // ETH
      oracle::set_price<ETH>(
        &oracle_admin_cap,
        &mut oracle_storage,
        INITIAL_ETH_PRICE,
        8,
        ctx(test)
      );

       // ADA
      oracle::set_price<ADA>(
        &oracle_admin_cap,
        &mut oracle_storage,
        INITIAL_ADA_PRICE,
        9,
        ctx(test)
      );

      test::return_to_address(alice, oracle_admin_cap);
      test::return_shared(oracle_storage);
    };

    next_tx(test, alice);
    {
      let whirpool_admin_cap = test::take_from_address<WhirpoolAdminCap>(test, alice);
      let whirpool_storage = test::take_shared<WhirpoolStorage>(test);
      let account_storage = test::take_shared<AccountStorage>(test);

      whirpool::create_market<BTC>(
        &whirpool_admin_cap,
        &mut whirpool_storage,
        &mut account_storage,
        BTC_BORROW_CAP,
        BTC_BORROW_CAP * 2,
        700000000, // 70% ltv
        500, // allocation points
        50000000, // 5% penalty fee
        200000000, // 20% protocol fee
        BTC_DECIMALS,
        ctx(test)
      );

      whirpool::create_market<ETH>(
        &whirpool_admin_cap,
        &mut whirpool_storage,
        &mut account_storage,
        ETH_BORROW_CAP,
        ETH_BORROW_CAP * 2,
        650000000, // 65% ltv
        700, // allocation points
        70000000, // 7% penalty fee
        100000000, // 10% protocol fee
        ETH_DECIMALS,
        ctx(test)
      );


      whirpool::create_market<ADA>(
        &whirpool_admin_cap,
        &mut whirpool_storage,
        &mut account_storage,
        ADA_BORROW_CAP,
        ADA_BORROW_CAP * 2,
        500000000, // 50% ltv
        900, // allocation points
        100000000, // 10% penalty fee
        200000000, // 20% protocol fee
        ADA_DECIMALS,
        ctx(test)
      );
      
      test::return_to_address(alice, whirpool_admin_cap);
      test::return_shared(whirpool_storage);
      test::return_shared(account_storage);
    };
  }

  fun test_deposit_(test: &mut Scenario) {
    init_test(test);

    let (alice, bob) = people();

    next_tx(test, alice);
    {
      let whirpool_storage = test::take_shared<WhirpoolStorage>(test);
      let account_storage = test::take_shared<AccountStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);
      let dnr_storage = test::take_shared<DineroStorage>(test);

      let coin_ipx = whirpool::deposit<BTC>(
        &mut whirpool_storage,
        &mut account_storage,
        &interest_rate_model_storage,
        &mut ipx_storage,
        &dnr_storage,
        mint<BTC>(10, BTC_DECIMALS, ctx(test)),
        ctx(test)
      );

      let (collateral, loan, collateral_rewards_paid, loan_rewards_paid) = whirpool::get_account_info<BTC>(&account_storage, alice);

      assert_eq(burn(coin_ipx), 0);
      assert_eq(collateral, 10 * math::pow(10, BTC_DECIMALS));
      assert_eq(loan, 0);
      assert_eq(collateral_rewards_paid, 0);
      assert_eq(loan_rewards_paid, 0);

      test::return_shared(dnr_storage);
      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(account_storage);
      test::return_shared(whirpool_storage);
    };

    advance_epoch(test, alice, 10);
    next_tx(test, alice);
    {
      let whirpool_storage = test::take_shared<WhirpoolStorage>(test);
      let account_storage = test::take_shared<AccountStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);
      let dnr_storage = test::take_shared<DineroStorage>(test);

      let coin_ipx = whirpool::deposit<BTC>(
        &mut whirpool_storage,
        &mut account_storage,
        &interest_rate_model_storage,
        &mut ipx_storage,
        &dnr_storage,
        mint<BTC>(5, BTC_DECIMALS, ctx(test)),
        ctx(test)
      );

      let (collateral, loan, collateral_rewards_paid, loan_rewards_paid) = whirpool::get_account_info<BTC>(&account_storage, alice);

      let collateral_rewards_per_share = calculate_btc_market_rewards(10, 10 * BTC_DECIMALS_FACTOR);

      assert_eq((burn(coin_ipx) as u256), collateral_rewards_per_share * (10 * BTC_DECIMALS_FACTOR as u256) / BTC_DECIMALS_FACTOR);
      assert_eq(collateral, 15 * math::pow(10, BTC_DECIMALS));
      assert_eq(loan, 0);
      assert_eq(collateral_rewards_paid, (collateral_rewards_per_share * (15 * BTC_DECIMALS_FACTOR)) / BTC_DECIMALS_FACTOR);
      assert_eq(loan_rewards_paid, 0);

      test::return_shared(dnr_storage);
      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(account_storage);
      test::return_shared(whirpool_storage);
    };

    advance_epoch(test, bob, 5);
    next_tx(test, bob);
    {
      let whirpool_storage = test::take_shared<WhirpoolStorage>(test);
      let account_storage = test::take_shared<AccountStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);
      let dnr_storage = test::take_shared<DineroStorage>(test);

      let (_, _, _, _, _, _, _, _, _, prev_collateral_rewards_per_share, _, _, _, _, _ ) = whirpool::get_market_info<BTC>(&whirpool_storage);

      let coin_ipx = whirpool::deposit<BTC>(
        &mut whirpool_storage,
        &mut account_storage,
        &interest_rate_model_storage,
        &mut ipx_storage,
        &dnr_storage,
        mint<BTC>(7, BTC_DECIMALS, ctx(test)),
        ctx(test)
      );

      let (collateral, loan, collateral_rewards_paid, loan_rewards_paid) = whirpool::get_account_info<BTC>(&account_storage, bob);

      let collateral_rewards_per_share = calculate_btc_market_rewards(5, 15 * BTC_DECIMALS_FACTOR) + prev_collateral_rewards_per_share;

      assert_eq((burn(coin_ipx) as u256), 0);
      assert_eq((collateral as u256), 7 * BTC_DECIMALS_FACTOR);
      assert_eq(loan, 0);
      assert_eq(collateral_rewards_paid, (collateral_rewards_per_share * (7 * BTC_DECIMALS_FACTOR)) / BTC_DECIMALS_FACTOR);
      assert_eq(loan_rewards_paid, 0);

      test::return_shared(dnr_storage);
      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(account_storage);
      test::return_shared(whirpool_storage);
    };    
  }

  #[test]
  fun test_deposit() {
    let scenario = scenario();
    test_deposit_(&mut scenario);
    test::end(scenario);
  }

  fun test_withdraw_(test: &mut Scenario) {
    init_test(test);

    let (alice, bob) = people();

    next_tx(test, alice);
    {
      let whirpool_storage = test::take_shared<WhirpoolStorage>(test);
      let account_storage = test::take_shared<AccountStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);
      let dnr_storage = test::take_shared<DineroStorage>(test);
      let oracle_storage = test::take_shared<OracleStorage>(test);

     burn(whirpool::deposit<BTC>(
        &mut whirpool_storage,
        &mut account_storage,
        &interest_rate_model_storage,
        &mut ipx_storage,
        &dnr_storage,
        mint<BTC>(10, BTC_DECIMALS, ctx(test)),
        ctx(test)
     ));

      let (coin_btc, coin_ipx) = whirpool::withdraw<BTC>(
        &mut whirpool_storage, 
        &mut account_storage,
        &interest_rate_model_storage, 
        &mut ipx_storage, 
        &dnr_storage, 
        &oracle_storage, 
        (3 * BTC_DECIMALS_FACTOR as u64), 
        ctx(test)
      );

      let (collateral, loan, collateral_rewards_paid, loan_rewards_paid) = whirpool::get_account_info<BTC>(&account_storage, alice);

      assert_eq(burn(coin_btc), (3 * BTC_DECIMALS_FACTOR as u64));
      assert_eq(burn(coin_ipx), 0);
      assert_eq(collateral, (7 * BTC_DECIMALS_FACTOR as u64));
      assert_eq(loan, 0);
      assert_eq(collateral_rewards_paid, 0);
      assert_eq(loan_rewards_paid, 0);

      test::return_shared(dnr_storage);
      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(account_storage);
      test::return_shared(whirpool_storage); 
      test::return_shared(oracle_storage);     
    };

    advance_epoch(test, alice, 6);
    {
      let whirpool_storage = test::take_shared<WhirpoolStorage>(test);
      let account_storage = test::take_shared<AccountStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);
      let dnr_storage = test::take_shared<DineroStorage>(test);
      let oracle_storage = test::take_shared<OracleStorage>(test);

      let (coin_btc, coin_ipx) = whirpool::withdraw<BTC>(
        &mut whirpool_storage, 
        &mut account_storage,
        &interest_rate_model_storage, 
        &mut ipx_storage, 
        &dnr_storage, 
        &oracle_storage, 
        (4 * BTC_DECIMALS_FACTOR as u64), 
        ctx(test)
      );

      let (collateral, loan, collateral_rewards_paid, loan_rewards_paid) = whirpool::get_account_info<BTC>(&account_storage, alice);

      let collateral_rewards_per_share = calculate_btc_market_rewards(6, 7 * BTC_DECIMALS_FACTOR);

      assert_eq(burn(coin_btc), (4 * BTC_DECIMALS_FACTOR as u64));
      assert_eq((burn(coin_ipx) as u256), collateral_rewards_per_share * (7 * BTC_DECIMALS_FACTOR)/ BTC_DECIMALS_FACTOR);
      assert_eq(collateral, (3 * BTC_DECIMALS_FACTOR as u64));
      assert_eq(loan, 0);
      assert_eq(collateral_rewards_paid, collateral_rewards_per_share * (3 * BTC_DECIMALS_FACTOR) / BTC_DECIMALS_FACTOR);
      assert_eq(loan_rewards_paid, 0);

      test::return_shared(dnr_storage);
      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(account_storage);
      test::return_shared(whirpool_storage); 
      test::return_shared(oracle_storage);         
    };

    next_tx(test, bob);
    {
      let whirpool_storage = test::take_shared<WhirpoolStorage>(test);
      let account_storage = test::take_shared<AccountStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);
      let dnr_storage = test::take_shared<DineroStorage>(test);

      burn(whirpool::deposit<BTC>(
        &mut whirpool_storage,
        &mut account_storage,
        &interest_rate_model_storage,
        &mut ipx_storage,
        &dnr_storage,
        mint<BTC>(12, BTC_DECIMALS, ctx(test)),
        ctx(test)
      ));

      test::return_shared(dnr_storage);
      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(account_storage);
      test::return_shared(whirpool_storage); 
    };

    advance_epoch(test, bob, 10);
    {
      let whirpool_storage = test::take_shared<WhirpoolStorage>(test);
      let account_storage = test::take_shared<AccountStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);
      let dnr_storage = test::take_shared<DineroStorage>(test);
      let oracle_storage = test::take_shared<OracleStorage>(test);

      let (_, _, _, _, _, _, _, _, _, prev_collateral_rewards_per_share, _, _, _, _, _ ) = whirpool::get_market_info<BTC>(&whirpool_storage);

      let (_, _, prev_collateral_rewards_paid, _) = whirpool::get_account_info<BTC>(&account_storage, bob);

      let (coin_btc, coin_ipx) = whirpool::withdraw<BTC>(
        &mut whirpool_storage, 
        &mut account_storage,
        &interest_rate_model_storage, 
        &mut ipx_storage, 
        &dnr_storage, 
        &oracle_storage, 
        (5 * BTC_DECIMALS_FACTOR as u64), 
        ctx(test)
      );

      let (collateral, loan, collateral_rewards_paid, loan_rewards_paid) = whirpool::get_account_info<BTC>(&account_storage, bob);

      let collateral_rewards_per_share = calculate_btc_market_rewards(10, 15 * BTC_DECIMALS_FACTOR) + prev_collateral_rewards_per_share; 

      assert_eq(burn(coin_btc), (5 * BTC_DECIMALS_FACTOR as u64));
      assert_eq((burn(coin_ipx) as u256), (collateral_rewards_per_share * (12 * BTC_DECIMALS_FACTOR)/ BTC_DECIMALS_FACTOR) - prev_collateral_rewards_paid);
      assert_eq(collateral, (7 * BTC_DECIMALS_FACTOR as u64));
      assert_eq(loan, 0);
      assert_eq(collateral_rewards_paid, collateral_rewards_per_share * (7 * BTC_DECIMALS_FACTOR) / BTC_DECIMALS_FACTOR);
      assert_eq(loan_rewards_paid, 0);

      test::return_shared(dnr_storage);
      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(account_storage);
      test::return_shared(whirpool_storage); 
      test::return_shared(oracle_storage);  
    };
  }

  #[test]
  fun test_withdraw() {
    let scenario = scenario();
    test_withdraw_(&mut scenario);
    test::end(scenario);    
  }

  fun test_borrow_(test: &mut Scenario) {
    init_test(test);

    let (alice, bob) = people();

    next_tx(test, alice);
    {
      let whirpool_storage = test::take_shared<WhirpoolStorage>(test);
      let account_storage = test::take_shared<AccountStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);
      let dnr_storage = test::take_shared<DineroStorage>(test);

      burn(whirpool::deposit<BTC>(
        &mut whirpool_storage,
        &mut account_storage,
        &interest_rate_model_storage,
        &mut ipx_storage,
        &dnr_storage,
        mint<BTC>(10, BTC_DECIMALS, ctx(test)),
        ctx(test)
       ));

      test::return_shared(dnr_storage);
      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(account_storage);
      test::return_shared(whirpool_storage); 
    };

    next_tx(test, bob);
    {
      let whirpool_storage = test::take_shared<WhirpoolStorage>(test);
      let account_storage = test::take_shared<AccountStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);
      let dnr_storage = test::take_shared<DineroStorage>(test);

      burn(whirpool::deposit<BTC>(
        &mut whirpool_storage,
        &mut account_storage,
        &interest_rate_model_storage,
        &mut ipx_storage,
        &dnr_storage,
        mint<BTC>(10, BTC_DECIMALS, ctx(test)),
        ctx(test)
       ));

      burn(whirpool::deposit<ETH>(
        &mut whirpool_storage,
        &mut account_storage,
        &interest_rate_model_storage,
        &mut ipx_storage,
        &dnr_storage,
        mint<ETH>(300, ETH_DECIMALS, ctx(test)),
        ctx(test)
       ));

      test::return_shared(dnr_storage);
      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(account_storage);
      test::return_shared(whirpool_storage); 
    };

    next_tx(test, alice);
    {
      let whirpool_storage = test::take_shared<WhirpoolStorage>(test);
      let account_storage = test::take_shared<AccountStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);
      let dnr_storage = test::take_shared<DineroStorage>(test);
      let oracle_storage = test::take_shared<OracleStorage>(test);

      let borrow_value = (99 * ETH_DECIMALS_FACTOR as u64);

      whirpool::enter_market<BTC>(&mut account_storage, ctx(test));

      let (coin_eth, coin_ipx) = whirpool::borrow<ETH>(
        &mut whirpool_storage,
        &mut account_storage,
        &interest_rate_model_storage,
        &mut ipx_storage,
        &dnr_storage,
        &oracle_storage,
        borrow_value,
        ctx(test)
       );

      let (collateral, loan, collateral_rewards_paid, loan_rewards_paid) = whirpool::get_account_info<ETH>(&account_storage, alice);
 
      assert_eq(burn(coin_eth), borrow_value);
      assert_eq(burn(coin_ipx), 0); 
      assert_eq(collateral, 0);
      assert_eq(collateral_rewards_paid, 0);
      assert_eq(loan, borrow_value);
      assert_eq(loan_rewards_paid, 0);

      test::return_shared(dnr_storage);
      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(account_storage);
      test::return_shared(whirpool_storage); 
      test::return_shared(oracle_storage); 
    };

    advance_epoch(test, alice, 5);
    {
      let whirpool_storage = test::take_shared<WhirpoolStorage>(test);
      let account_storage = test::take_shared<AccountStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);
      let dnr_storage = test::take_shared<DineroStorage>(test);
      let oracle_storage = test::take_shared<OracleStorage>(test);

      // So we can borrow more
      burn(whirpool::deposit<BTC>(
        &mut whirpool_storage,
        &mut account_storage,
        &interest_rate_model_storage,
        &mut ipx_storage,
        &dnr_storage,
        mint<BTC>(10, BTC_DECIMALS, ctx(test)),
        ctx(test)
       ));

      let borrow_value = (10 * ETH_DECIMALS_FACTOR as u64);

      let interest_rate_per_epoch = whirpool::get_borrow_rate_per_epoch<ETH>(
        &whirpool_storage,
        &interest_rate_model_storage,
        &dnr_storage
      );

      let (_, _, _, _, _, _, _, _, _, _, _, _, _, total_principal, total_borrows) = whirpool::get_market_info<ETH>(&whirpool_storage);

      let accumulated_interest_rate = interest_rate_per_epoch * 5;
      let new_total_borrows = total_borrows + fmul(total_borrows, accumulated_interest_rate);

      // round up
      let added_principal = ((borrow_value * total_principal) / new_total_borrows) + 1;

      let (coin_eth, coin_ipx) = whirpool::borrow<ETH>(
        &mut whirpool_storage,
        &mut account_storage,
        &interest_rate_model_storage,
        &mut ipx_storage,
        &dnr_storage,
        &oracle_storage,
        borrow_value,
        ctx(test)
       );

      // 5 epoch rewards
      let loan_rewards_per_share = calculate_eth_market_rewards(5, 99 * ETH_DECIMALS_FACTOR);

      let (collateral, loan, collateral_rewards_paid, loan_rewards_paid) = whirpool::get_account_info<ETH>(&account_storage, alice);
      let new_principal = 99 * ETH_DECIMALS_FACTOR + (added_principal as u256);

      assert_eq(burn(coin_eth), borrow_value);  
      assert_eq((burn(coin_ipx) as u256), loan_rewards_per_share * 99); 
      assert_eq(collateral, 0);
      assert_eq((loan as u256), new_principal);
      assert_eq(collateral_rewards_paid, 0);
      assert_eq(loan_rewards_paid, loan_rewards_per_share * new_principal / ETH_DECIMALS_FACTOR);

      test::return_shared(dnr_storage);
      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(account_storage);
      test::return_shared(whirpool_storage); 
      test::return_shared(oracle_storage); 
    };

    advance_epoch(test, alice, 4);
    {
      let whirpool_storage = test::take_shared<WhirpoolStorage>(test);
      let account_storage = test::take_shared<AccountStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);
      let dnr_storage = test::take_shared<DineroStorage>(test);
      let oracle_storage = test::take_shared<OracleStorage>(test);

      let borrow_value = (5 * ETH_DECIMALS_FACTOR as u64);

      let interest_rate_per_epoch = whirpool::get_borrow_rate_per_epoch<ETH>(
        &whirpool_storage,
        &interest_rate_model_storage,
        &dnr_storage
      );

      let (_, _, _, _, _, _, _, _, _, _, prev_loan_rewards_per_share, _, _, total_principal, total_borrows) = whirpool::get_market_info<ETH>(&whirpool_storage);

      let accumulated_interest_rate = interest_rate_per_epoch * 4;
      let new_total_borrows = total_borrows + fmul(total_borrows, accumulated_interest_rate);

      // round up
      let added_principal = ((borrow_value * total_principal) / new_total_borrows) + 1;

      let (_, prev_loan, _, prev_loan_rewards_paid) = whirpool::get_account_info<ETH>(&account_storage, alice);

      let (coin_eth, coin_ipx) = whirpool::borrow<ETH>(
        &mut whirpool_storage,
        &mut account_storage,
        &interest_rate_model_storage,
        &mut ipx_storage,
        &dnr_storage,
        &oracle_storage,
        borrow_value,
        ctx(test)
       );

      // 5 epoch rewards
      let loan_rewards_per_share = calculate_eth_market_rewards(4, (total_principal as u256)) + prev_loan_rewards_per_share;

      let (collateral, loan, collateral_rewards_paid, loan_rewards_paid) = whirpool::get_account_info<ETH>(&account_storage, alice);
      let new_principal = prev_loan + added_principal;

      assert_eq(burn(coin_eth), borrow_value);  
      assert_eq((burn(coin_ipx) as u256), (loan_rewards_per_share * (prev_loan as u256) / ETH_DECIMALS_FACTOR) - prev_loan_rewards_paid); 
      assert_eq(collateral, 0);
      assert_eq(loan, new_principal);
      assert_eq(collateral_rewards_paid, 0);
      assert_eq(loan_rewards_paid, loan_rewards_per_share * (new_principal as u256) / ETH_DECIMALS_FACTOR);

      test::return_shared(dnr_storage);
      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(account_storage);
      test::return_shared(whirpool_storage); 
      test::return_shared(oracle_storage); 
    };
  }

  #[test]
  fun test_borrow() {
    let scenario = scenario();
    test_borrow_(&mut scenario);
    test::end(scenario);    
  }

  fun test_repay_(test: &mut Scenario) {
    init_test(test);

    let (alice, bob) = people();

    next_tx(test, alice);
    {
      let whirpool_storage = test::take_shared<WhirpoolStorage>(test);
      let account_storage = test::take_shared<AccountStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);
      let dnr_storage = test::take_shared<DineroStorage>(test);

      burn(whirpool::deposit<BTC>(
        &mut whirpool_storage,
        &mut account_storage,
        &interest_rate_model_storage,
        &mut ipx_storage,
        &dnr_storage,
        mint<BTC>(10, BTC_DECIMALS, ctx(test)),
        ctx(test)
       ));

      test::return_shared(dnr_storage);
      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(account_storage);
      test::return_shared(whirpool_storage); 
    };

    next_tx(test, bob);
    {
      let whirpool_storage = test::take_shared<WhirpoolStorage>(test);
      let account_storage = test::take_shared<AccountStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);
      let dnr_storage = test::take_shared<DineroStorage>(test);

      burn(whirpool::deposit<BTC>(
        &mut whirpool_storage,
        &mut account_storage,
        &interest_rate_model_storage,
        &mut ipx_storage,
        &dnr_storage,
        mint<BTC>(10, BTC_DECIMALS, ctx(test)),
        ctx(test)
       ));

      burn(whirpool::deposit<ETH>(
        &mut whirpool_storage,
        &mut account_storage,
        &interest_rate_model_storage,
        &mut ipx_storage,
        &dnr_storage,
        mint<ETH>(300, ETH_DECIMALS, ctx(test)),
        ctx(test)
       ));

      test::return_shared(dnr_storage);
      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(account_storage);
      test::return_shared(whirpool_storage); 
    };

    next_tx(test, alice);
    {
      let whirpool_storage = test::take_shared<WhirpoolStorage>(test);
      let account_storage = test::take_shared<AccountStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);
      let dnr_storage = test::take_shared<DineroStorage>(test);
      let oracle_storage = test::take_shared<OracleStorage>(test);

      let borrow_value = (50 * ETH_DECIMALS_FACTOR as u64);

      whirpool::enter_market<BTC>(&mut account_storage, ctx(test));

      let (coin_eth, coin_ipx) = whirpool::borrow<ETH>(
        &mut whirpool_storage,
        &mut account_storage,
        &interest_rate_model_storage,
        &mut ipx_storage,
        &dnr_storage,
        &oracle_storage,
        borrow_value,
        ctx(test)
       );

      burn(coin_eth);
      burn(coin_ipx);

      test::return_shared(dnr_storage);
      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(account_storage);
      test::return_shared(whirpool_storage); 
      test::return_shared(oracle_storage); 
    };

    advance_epoch(test, alice, 5);
    {
      let whirpool_storage = test::take_shared<WhirpoolStorage>(test);
      let account_storage = test::take_shared<AccountStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);
      let dnr_storage = test::take_shared<DineroStorage>(test);

      let coin_ipx = whirpool::repay<ETH>(
        &mut whirpool_storage,
        &mut account_storage,
        &mut interest_rate_model_storage,
        &mut ipx_storage,
        &dnr_storage,
        mint<ETH>(30, ETH_DECIMALS, ctx(test)),
        (25 * ETH_DECIMALS_FACTOR as u64),
        ctx(test)
      );

      let loan_rewards_per_share = calculate_eth_market_rewards(5, 50 * ETH_DECIMALS_FACTOR);
      let (_, loan, _, loan_rewards_paid) = whirpool::get_account_info<ETH>(&account_storage, alice);

      assert_eq((burn(coin_ipx) as u256), loan_rewards_per_share * 50);
      assert_eq(loan, (25 * ETH_DECIMALS_FACTOR as u64));
      assert_eq(loan_rewards_paid, loan_rewards_per_share * 25);

      test::return_shared(dnr_storage);
      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(account_storage);
      test::return_shared(whirpool_storage); 
    };

    advance_epoch(test, alice, 7);
    {
      let whirpool_storage = test::take_shared<WhirpoolStorage>(test);
      let account_storage = test::take_shared<AccountStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);
      let dnr_storage = test::take_shared<DineroStorage>(test);

      let (_, _, _, _, _, _, _, _, _, _, prev_loan_rewards_per_share, _, _, _, _) = whirpool::get_market_info<ETH>(&whirpool_storage);

      let (_, prev_loan, _, prev_loan_rewards_paid) = whirpool::get_account_info<ETH>(&account_storage, alice);

      let coin_ipx = whirpool::repay<ETH>(
        &mut whirpool_storage,
        &mut account_storage,
        &mut interest_rate_model_storage,
        &mut ipx_storage,
        &dnr_storage,
        mint<ETH>(40, ETH_DECIMALS, ctx(test)),
        (25 * ETH_DECIMALS_FACTOR as u64),
        ctx(test)
      );

      let loan_rewards_per_share = calculate_eth_market_rewards(7, 25 * ETH_DECIMALS_FACTOR) + prev_loan_rewards_per_share;
      let (_, loan, _, loan_rewards_paid) = whirpool::get_account_info<ETH>(&account_storage, alice);

      assert_eq((burn(coin_ipx) as u256), (loan_rewards_per_share * (prev_loan as u256) / ETH_DECIMALS_FACTOR) - prev_loan_rewards_paid);
      assert_eq(loan, 0);
      assert_eq(loan_rewards_paid, 0);

      test::return_shared(dnr_storage);
      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(account_storage);
      test::return_shared(whirpool_storage); 
    };
  }

  #[test]
  fun test_repay() {
    let scenario = scenario();
    test_repay_(&mut scenario);
    test::end(scenario);    
  }

  // utils

  fun calculate_btc_market_rewards(num_of_epochs: u256, total_principal: u256): u256 {
    ((num_of_epochs * (100 * IPX_DECIMALS_FACTOR) * 500) / 2100/ 2) * BTC_DECIMALS_FACTOR / total_principal  
  }

  fun calculate_eth_market_rewards(num_of_epochs: u256, total_principal: u256): u256 {
    ((num_of_epochs * (100 * IPX_DECIMALS_FACTOR) * 700) / 2100/ 2) * ETH_DECIMALS_FACTOR / total_principal
  }
} 

