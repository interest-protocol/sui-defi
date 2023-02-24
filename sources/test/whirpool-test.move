#[test_only]
module interest_protocol::whirpool_test {
  use std::vector;

  use sui::test_scenario::{Self as test, Scenario, next_tx, ctx};
  use sui::test_utils::{assert_eq};
  use sui::coin::{destroy_for_testing as burn};
  use sui::math;

  use interest_protocol::whirpool::{Self, WhirpoolAdminCap, WhirpoolStorage, AccountStorage};
  use interest_protocol::ipx::{Self, IPXStorage};
  use interest_protocol::dnr::{Self, DineroStorage, DNR};
  use interest_protocol::oracle::{Self, OracleStorage, OracleAdminCap};
  use interest_protocol::interest_rate_model::{Self as model, InterestRateModelStorage};
  use interest_protocol::math::{fmul};
  use interest_protocol::utils::{get_coin_info};
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
  const ADA_BORROW_CAP: u64 = 100000000000000; // 10M 7 decimals
  const BTC_DECIMALS: u8 = 9;
  const ETH_DECIMALS: u8 = 8;
  const ADA_DECIMALS: u8 = 7;
  const DNR_DECIMALS: u8 = 7;
  const IPX_DECIMALS_FACTOR: u256 = 1000000000;
  const BTC_DECIMALS_FACTOR: u256 = 1000000000;
  const ETH_DECIMALS_FACTOR: u256 = 100000000;
  const ADA_DECIMALS_FACTOR: u256 = 10000000;
  const INITIAL_RESERVE_FACTOR_MANTISSA: u64 = 200000000; // 0.2e9 or 20%

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

  #[test]
  #[expected_failure(abort_code = whirpool::ERROR_DNR_OPERATION_NOT_ALLOWED)]
  fun test_fail_deposit_dnr() {
    let scenario = scenario();

    let test = &mut scenario;

    init_test(test);

    let (alice, _) = people();

    next_tx(test, alice);
    {
      let whirpool_storage = test::take_shared<WhirpoolStorage>(test);
      let account_storage = test::take_shared<AccountStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);
      let dnr_storage = test::take_shared<DineroStorage>(test);

      burn(whirpool::deposit<DNR>(
        &mut whirpool_storage,
        &mut account_storage,
        &interest_rate_model_storage,
        &mut ipx_storage,
        &dnr_storage,
        mint<DNR>(10, DNR_DECIMALS, ctx(test)),
        ctx(test)
      ));

      test::return_shared(dnr_storage);
      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(account_storage);
      test::return_shared(whirpool_storage);
   };

    test::end(scenario);
  }

  #[test]
  #[expected_failure(abort_code = whirpool::ERROR_MARKET_IS_PAUSED)]
  fun test_fail_deposit_paused() {
    let scenario = scenario();

    let test = &mut scenario;

    init_test(test);

    let (alice, _) = people();

    next_tx(test, alice);
    {
      let whirpool_storage = test::take_shared<WhirpoolStorage>(test);
      let account_storage = test::take_shared<AccountStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);
      let dnr_storage = test::take_shared<DineroStorage>(test); 
      let whirpool_admin_cap = test::take_from_address<WhirpoolAdminCap>(test, alice);

      whirpool::pause_market<BTC>(&whirpool_admin_cap, &mut whirpool_storage);


      burn(whirpool::deposit<BTC>(
        &mut whirpool_storage,
        &mut account_storage,
        &interest_rate_model_storage,
        &mut ipx_storage,
        &dnr_storage,
        mint<BTC>(10, DNR_DECIMALS, ctx(test)),
        ctx(test)
      ));

      test::return_shared(dnr_storage);
      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(account_storage);
      test::return_shared(whirpool_storage);
      test::return_to_address(alice, whirpool_admin_cap);
   };

    test::end(scenario);
  }

  #[test]
  #[expected_failure(abort_code = whirpool::ERROR_MAX_COLLATERAL_REACHED)]
  fun test_fail_deposit_borrow_cap_reached() {
    let scenario = scenario();

    let test = &mut scenario;

    init_test(test);

    let (alice, _) = people();

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
        mint<BTC>(BTC_BORROW_CAP + 1, DNR_DECIMALS, ctx(test)),
        ctx(test)
      ));

      test::return_shared(dnr_storage);
      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(account_storage);
      test::return_shared(whirpool_storage);
   };

    test::end(scenario);
  }

  #[test]
  #[expected_failure(abort_code = whirpool::ERROR_DNR_OPERATION_NOT_ALLOWED)]
  fun test_fail_withdraw_dnr() {
    let scenario = scenario();

    let test = &mut scenario;

    init_test(test);

    let (alice, _) = people();

    next_tx(test, alice);
    {
    let whirpool_storage = test::take_shared<WhirpoolStorage>(test);
      let account_storage = test::take_shared<AccountStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);
      let dnr_storage = test::take_shared<DineroStorage>(test);
      let oracle_storage = test::take_shared<OracleStorage>(test);

      let (coin_btc, coin_ipx) = whirpool::withdraw<DNR>(
        &mut whirpool_storage, 
        &mut account_storage,
        &interest_rate_model_storage, 
        &mut ipx_storage, 
        &dnr_storage, 
        &oracle_storage, 
        0, 
        ctx(test)
      );

      burn(coin_btc);
      burn(coin_ipx);

      test::return_shared(dnr_storage);
      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(account_storage);
      test::return_shared(whirpool_storage); 
      test::return_shared(oracle_storage); 
   };

    test::end(scenario);
  }

  #[test]
  #[expected_failure(abort_code = whirpool::ERROR_NOT_ENOUGH_SHARES_IN_THE_ACCOUNT)]
  fun test_fail_withdraw_not_enough_shares() {
    let scenario = scenario();

    let test = &mut scenario;

    init_test(test);

    let (alice, _) = people();

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
        (11 * BTC_DECIMALS_FACTOR as u64), 
        ctx(test)
      );

      burn(coin_btc);
      burn(coin_ipx);

      test::return_shared(dnr_storage);
      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(account_storage);
      test::return_shared(whirpool_storage); 
      test::return_shared(oracle_storage); 
   };

    test::end(scenario);
  }

  #[test]
  #[expected_failure(abort_code = whirpool::ERROR_NOT_ENOUGH_CASH_TO_WITHDRAW)]
  fun test_fail_withdraw_no_cash() {
    let scenario = scenario();

    let test = &mut scenario;

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
      let oracle_storage = test::take_shared<OracleStorage>(test);

      burn(whirpool::deposit<ETH>(
        &mut whirpool_storage,
        &mut account_storage,
        &interest_rate_model_storage,
        &mut ipx_storage,
        &dnr_storage,
        mint<ETH>(200, ETH_DECIMALS, ctx(test)),
        ctx(test)
      ));

      whirpool::enter_market<ETH>(&mut account_storage, ctx(test));

      let (coin_eth, coin_ipx) = whirpool::borrow<BTC>(
        &mut whirpool_storage,
        &mut account_storage,
        &interest_rate_model_storage,
        &mut ipx_storage,
        &dnr_storage,
        &oracle_storage,
        (5 * BTC_DECIMALS_FACTOR as u64), 
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

    next_tx(test, alice);
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
        (6 * BTC_DECIMALS_FACTOR as u64), 
        ctx(test)
      );

      burn(coin_btc);
      burn(coin_ipx);

      test::return_shared(dnr_storage);
      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(account_storage);
      test::return_shared(whirpool_storage); 
      test::return_shared(oracle_storage); 
   };

    test::end(scenario);
  }

  #[test]
  #[expected_failure(abort_code = whirpool::ERROR_MARKET_IS_PAUSED)]
  fun test_fail_withdraw_paused() {
    let scenario = scenario();

    let test = &mut scenario;

    init_test(test);

    let (alice, _) = people();

    next_tx(test, alice);
    {
      let whirpool_storage = test::take_shared<WhirpoolStorage>(test);
      let account_storage = test::take_shared<AccountStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);
      let dnr_storage = test::take_shared<DineroStorage>(test);
      let oracle_storage = test::take_shared<OracleStorage>(test);
      let whirpool_admin_cap = test::take_from_address<WhirpoolAdminCap>(test, alice);

      burn(whirpool::deposit<BTC>(
        &mut whirpool_storage,
        &mut account_storage,
        &interest_rate_model_storage,
        &mut ipx_storage,
        &dnr_storage,
        mint<BTC>(10, BTC_DECIMALS, ctx(test)),
        ctx(test)
      ));

      whirpool::pause_market<BTC>(&whirpool_admin_cap, &mut whirpool_storage);

      let (coin_btc, coin_ipx) = whirpool::withdraw<BTC>(
        &mut whirpool_storage, 
        &mut account_storage,
        &interest_rate_model_storage, 
        &mut ipx_storage, 
        &dnr_storage, 
        &oracle_storage, 
        1, 
        ctx(test)
      );

      burn(coin_btc);
      burn(coin_ipx);

      test::return_shared(dnr_storage);
      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(account_storage);
      test::return_shared(whirpool_storage); 
      test::return_shared(oracle_storage); 
      test::return_to_address(alice, whirpool_admin_cap);
    };

    test::end(scenario);
  }

  #[test]
  #[expected_failure(abort_code = whirpool::ERROR_USER_IS_INSOLVENT)]
  fun test_fail_withdraw_insolvent() {
    let scenario = scenario();

    let test = &mut scenario;

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

      whirpool::enter_market<BTC>(&mut account_storage, ctx(test));

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
      let oracle_storage = test::take_shared<OracleStorage>(test);

      burn(whirpool::deposit<ETH>(
        &mut whirpool_storage,
        &mut account_storage,
        &interest_rate_model_storage,
        &mut ipx_storage,
        &dnr_storage,
        mint<ETH>(100, ETH_DECIMALS, ctx(test)),
        ctx(test)
      ));

      whirpool::enter_market<BTC>(&mut account_storage, ctx(test));

      test::return_shared(dnr_storage);
      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(account_storage);
      test::return_shared(whirpool_storage); 
      test::return_shared(oracle_storage); 
   };

   next_tx(test, alice);
   {
      let whirpool_storage = test::take_shared<WhirpoolStorage>(test);
      let account_storage = test::take_shared<AccountStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);
      let dnr_storage = test::take_shared<DineroStorage>(test);
      let oracle_storage = test::take_shared<OracleStorage>(test);

      let (coin_eth, coin_ipx) = whirpool::borrow<ETH>(
        &mut whirpool_storage,
        &mut account_storage,
        &interest_rate_model_storage,
        &mut ipx_storage,
        &dnr_storage,
        &oracle_storage,
        (60 * ETH_DECIMALS_FACTOR as u64),
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

    next_tx(test, alice);
    {
      let whirpool_storage = test::take_shared<WhirpoolStorage>(test);
      let account_storage = test::take_shared<AccountStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);
      let dnr_storage = test::take_shared<DineroStorage>(test);
      let oracle_storage = test::take_shared<OracleStorage>(test);
      let whirpool_admin_cap = test::take_from_address<WhirpoolAdminCap>(test, alice);

      let (coin_btc, coin_ipx) = whirpool::withdraw<BTC>(
        &mut whirpool_storage, 
        &mut account_storage,
        &interest_rate_model_storage, 
        &mut ipx_storage, 
        &dnr_storage, 
        &oracle_storage, 
        (8 * BTC_DECIMALS_FACTOR as u64), 
        ctx(test)
      );

      burn(coin_btc);
      burn(coin_ipx);

      test::return_shared(dnr_storage);
      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(account_storage);
      test::return_shared(whirpool_storage); 
      test::return_shared(oracle_storage); 
      test::return_to_address(alice, whirpool_admin_cap);
    };

    test::end(scenario);
  }

  #[test]
  #[expected_failure(abort_code = whirpool::ERROR_DNR_OPERATION_NOT_ALLOWED)]
  fun test_fail_borrow() {
    let scenario = scenario();

    let test = &mut scenario;

    init_test(test);

    let (alice, _) = people();

    next_tx(test, alice);
    {
      let whirpool_storage = test::take_shared<WhirpoolStorage>(test);
      let account_storage = test::take_shared<AccountStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);
      let dnr_storage = test::take_shared<DineroStorage>(test);
      let oracle_storage = test::take_shared<OracleStorage>(test);

      let (coin_dnr, coin_ipx) = whirpool::borrow<DNR>(
        &mut whirpool_storage,
        &mut account_storage,
        &interest_rate_model_storage,
        &mut ipx_storage,
        &dnr_storage,
        &oracle_storage,
        0,
        ctx(test)
       );

       burn(coin_dnr);
       burn(coin_ipx);

      test::return_shared(dnr_storage);
      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(account_storage);
      test::return_shared(whirpool_storage); 
      test::return_shared(oracle_storage); 
   };

    test::end(scenario);
  }

  #[test]
  #[expected_failure(abort_code = whirpool::ERROR_NOT_ENOUGH_CASH_TO_LEND)]
  fun test_fail_borrow_not_enough_cash() {
    let scenario = scenario();

    let test = &mut scenario;

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

      whirpool::enter_market<BTC>(&mut account_storage, ctx(test));

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
      let oracle_storage = test::take_shared<OracleStorage>(test);

      burn(whirpool::deposit<ETH>(
        &mut whirpool_storage,
        &mut account_storage,
        &interest_rate_model_storage,
        &mut ipx_storage,
        &dnr_storage,
        mint<ETH>(10, ETH_DECIMALS, ctx(test)),
        ctx(test)
      ));

      whirpool::enter_market<BTC>(&mut account_storage, ctx(test));

      test::return_shared(dnr_storage);
      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(account_storage);
      test::return_shared(whirpool_storage); 
      test::return_shared(oracle_storage);    
    };

    next_tx(test, alice);
   {
      let whirpool_storage = test::take_shared<WhirpoolStorage>(test);
      let account_storage = test::take_shared<AccountStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);
      let dnr_storage = test::take_shared<DineroStorage>(test);
      let oracle_storage = test::take_shared<OracleStorage>(test);

      whirpool::enter_market<BTC>(&mut account_storage, ctx(test));

      let (coin_eth, coin_ipx) = whirpool::borrow<ETH>(
        &mut whirpool_storage,
        &mut account_storage,
        &interest_rate_model_storage,
        &mut ipx_storage,
        &dnr_storage,
        &oracle_storage,
        (11 * ETH_DECIMALS_FACTOR as u64),
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

    test::end(scenario);
  }

  #[test]
  #[expected_failure(abort_code = whirpool::ERROR_MARKET_IS_PAUSED)]
  fun test_fail_borrow_paused() {
    let scenario = scenario();

    let test = &mut scenario;

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

      whirpool::enter_market<BTC>(&mut account_storage, ctx(test));

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
      let oracle_storage = test::take_shared<OracleStorage>(test);

      burn(whirpool::deposit<ETH>(
        &mut whirpool_storage,
        &mut account_storage,
        &interest_rate_model_storage,
        &mut ipx_storage,
        &dnr_storage,
        mint<ETH>(10, ETH_DECIMALS, ctx(test)),
        ctx(test)
      ));

      whirpool::enter_market<BTC>(&mut account_storage, ctx(test));

      test::return_shared(dnr_storage);
      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(account_storage);
      test::return_shared(whirpool_storage); 
      test::return_shared(oracle_storage);    
    };

    next_tx(test, alice);
   {
      let whirpool_storage = test::take_shared<WhirpoolStorage>(test);
      let account_storage = test::take_shared<AccountStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);
      let dnr_storage = test::take_shared<DineroStorage>(test);
      let oracle_storage = test::take_shared<OracleStorage>(test);
      let whirpool_admin_cap = test::take_from_address<WhirpoolAdminCap>(test, alice);

      whirpool::enter_market<BTC>(&mut account_storage, ctx(test));
      whirpool::pause_market<ETH>(&whirpool_admin_cap, &mut whirpool_storage);

      let (coin_eth, coin_ipx) = whirpool::borrow<ETH>(
        &mut whirpool_storage,
        &mut account_storage,
        &interest_rate_model_storage,
        &mut ipx_storage,
        &dnr_storage,
        &oracle_storage,
        (2 * ETH_DECIMALS_FACTOR as u64),
        ctx(test)
       );

       burn(coin_eth);
       burn(coin_ipx);

      test::return_to_address(alice, whirpool_admin_cap);
      test::return_shared(dnr_storage);
      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(account_storage);
      test::return_shared(whirpool_storage); 
      test::return_shared(oracle_storage); 
   };

    test::end(scenario);
  }

  #[test]
  #[expected_failure(abort_code = whirpool::ERROR_BORROW_CAP_LIMIT_REACHED)]
  fun test_fail_borrow_cap_reached() {
    let scenario = scenario();

    let test = &mut scenario;

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

      whirpool::enter_market<BTC>(&mut account_storage, ctx(test));

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
      let oracle_storage = test::take_shared<OracleStorage>(test);

      burn(whirpool::deposit<ETH>(
        &mut whirpool_storage,
        &mut account_storage,
        &interest_rate_model_storage,
        &mut ipx_storage,
        &dnr_storage,
        mint<ETH>(10, ETH_DECIMALS, ctx(test)),
        ctx(test)
      ));

      whirpool::enter_market<BTC>(&mut account_storage, ctx(test));

      test::return_shared(dnr_storage);
      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(account_storage);
      test::return_shared(whirpool_storage); 
      test::return_shared(oracle_storage);    
    };

    next_tx(test, alice);
   {
      let whirpool_storage = test::take_shared<WhirpoolStorage>(test);
      let account_storage = test::take_shared<AccountStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);
      let dnr_storage = test::take_shared<DineroStorage>(test);
      let oracle_storage = test::take_shared<OracleStorage>(test);
      let whirpool_admin_cap = test::take_from_address<WhirpoolAdminCap>(test, alice);

      whirpool::enter_market<BTC>(&mut account_storage, ctx(test));
      whirpool::set_borrow_cap<ETH>(&whirpool_admin_cap, &mut whirpool_storage, (ETH_DECIMALS_FACTOR as u64));

      let (coin_eth, coin_ipx) = whirpool::borrow<ETH>(
        &mut whirpool_storage,
        &mut account_storage,
        &interest_rate_model_storage,
        &mut ipx_storage,
        &dnr_storage,
        &oracle_storage,
        (2 * ETH_DECIMALS_FACTOR as u64),
        ctx(test)
       );

       burn(coin_eth);
       burn(coin_ipx);

      test::return_to_address(alice, whirpool_admin_cap);
      test::return_shared(dnr_storage);
      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(account_storage);
      test::return_shared(whirpool_storage); 
      test::return_shared(oracle_storage); 
   };

    test::end(scenario);
  }

  #[test]
  #[expected_failure(abort_code = whirpool::ERROR_USER_IS_SOLVENT)]
  fun test_fail_borrow_insolvent() {
    let scenario = scenario();

    let test = &mut scenario;

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

      whirpool::enter_market<BTC>(&mut account_storage, ctx(test));

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
      let oracle_storage = test::take_shared<OracleStorage>(test);

      burn(whirpool::deposit<ETH>(
        &mut whirpool_storage,
        &mut account_storage,
        &interest_rate_model_storage,
        &mut ipx_storage,
        &dnr_storage,
        mint<ETH>(200, ETH_DECIMALS, ctx(test)),
        ctx(test)
      ));

      whirpool::enter_market<BTC>(&mut account_storage, ctx(test));

      test::return_shared(dnr_storage);
      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(account_storage);
      test::return_shared(whirpool_storage); 
      test::return_shared(oracle_storage);    
    };

    next_tx(test, alice);
   {
      let whirpool_storage = test::take_shared<WhirpoolStorage>(test);
      let account_storage = test::take_shared<AccountStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);
      let dnr_storage = test::take_shared<DineroStorage>(test);
      let oracle_storage = test::take_shared<OracleStorage>(test);
      let whirpool_admin_cap = test::take_from_address<WhirpoolAdminCap>(test, alice);

      whirpool::enter_market<BTC>(&mut account_storage, ctx(test));

      let (coin_eth, coin_ipx) = whirpool::borrow<ETH>(
        &mut whirpool_storage,
        &mut account_storage,
        &interest_rate_model_storage,
        &mut ipx_storage,
        &dnr_storage,
        &oracle_storage,
        (101 * ETH_DECIMALS_FACTOR as u64),
        ctx(test)
       );

       burn(coin_eth);
       burn(coin_ipx);

      test::return_to_address(alice, whirpool_admin_cap);
      test::return_shared(dnr_storage);
      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(account_storage);
      test::return_shared(whirpool_storage); 
      test::return_shared(oracle_storage); 
   };

    test::end(scenario);
  }

  #[test]
  #[expected_failure(abort_code = whirpool::ERROR_DNR_OPERATION_NOT_ALLOWED)]
  fun test_fail_repay_dnr() {
    let scenario = scenario();

    let test = &mut scenario;

    init_test(test);

    let (alice, _) = people();

    next_tx(test, alice);
    {
      let whirpool_storage = test::take_shared<WhirpoolStorage>(test);
      let account_storage = test::take_shared<AccountStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);
      let dnr_storage = test::take_shared<DineroStorage>(test);

      burn(whirpool::repay<DNR>(
        &mut whirpool_storage,
        &mut account_storage,
        &mut interest_rate_model_storage,
        &mut ipx_storage,
        &dnr_storage,
        mint<DNR>(30, ETH_DECIMALS, ctx(test)),
        0,
        ctx(test)
      ));

      test::return_shared(dnr_storage);
      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(account_storage);
      test::return_shared(whirpool_storage);
   };

    test::end(scenario);
  }

  #[test]
  #[expected_failure(abort_code = whirpool::ERROR_MARKET_IS_PAUSED)]
  fun test_fail_repay_paused() {
    let scenario = scenario();

    let test = &mut scenario;

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

      whirpool::enter_market<BTC>(&mut account_storage, ctx(test));

      let (coin_eth, coin_ipx) = whirpool::borrow<ETH>(
        &mut whirpool_storage,
        &mut account_storage,
        &interest_rate_model_storage,
        &mut ipx_storage,
        &dnr_storage,
        &oracle_storage,
        (10 * ETH_DECIMALS_FACTOR as u64),
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
    next_tx(test, alice);
    {
      let whirpool_storage = test::take_shared<WhirpoolStorage>(test);
      let account_storage = test::take_shared<AccountStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);
      let dnr_storage = test::take_shared<DineroStorage>(test);
      let whirpool_admin_cap = test::take_from_address<WhirpoolAdminCap>(test, alice);

      whirpool::pause_market<ETH>(&whirpool_admin_cap, &mut whirpool_storage);

      burn(whirpool::repay<ETH>(
        &mut whirpool_storage,
        &mut account_storage,
        &mut interest_rate_model_storage,
        &mut ipx_storage,
        &dnr_storage,
        mint<ETH>(10, ETH_DECIMALS, ctx(test)),
        0,
        ctx(test)
      ));

      test::return_to_address(alice, whirpool_admin_cap);
      test::return_shared(dnr_storage);
      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(account_storage);
      test::return_shared(whirpool_storage);
   };

    test::end(scenario);
  }

  #[test]
  fun test_exit_market() {
    let scenario = scenario();

    let test = &mut scenario;

    init_test(test);

    let (alice, _) = people();

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
        mint<BTC>(5, BTC_DECIMALS, ctx(test)),
        ctx(test)
      ));

      burn(whirpool::deposit<ADA>(
        &mut whirpool_storage,
        &mut account_storage,
        &interest_rate_model_storage,
        &mut ipx_storage,
        &dnr_storage,
        mint<ADA>(10000, ADA_DECIMALS, ctx(test)),
        ctx(test)
      ));

      whirpool::enter_market<BTC>(&mut account_storage, ctx(test));
      whirpool::enter_market<ADA>(&mut account_storage, ctx(test));

      let user_markets_in = whirpool::get_user_markets_in(&account_storage, alice);

      assert_eq(vector::contains(user_markets_in, &get_coin_info<BTC>()), true);
      assert_eq(vector::contains(user_markets_in, &get_coin_info<ADA>()), true);

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

      let (coin_btc, coin_ipx) = whirpool::borrow<BTC>(
        &mut whirpool_storage,
        &mut account_storage,
        &interest_rate_model_storage,
        &mut ipx_storage,
        &dnr_storage,
        &oracle_storage,
        (BTC_DECIMALS_FACTOR as u64),
        ctx(test)
       );

      burn(coin_btc);
      burn(coin_ipx);

      whirpool::exit_market<ADA>(
        &mut whirpool_storage,
        &mut account_storage,
        &interest_rate_model_storage,
        &dnr_storage,
        &oracle_storage,
        ctx(test)
      );

      let user_markets_in = whirpool::get_user_markets_in(&account_storage, alice);

      assert_eq(vector::contains(user_markets_in, &get_coin_info<BTC>()), true);
      assert_eq(vector::contains(user_markets_in, &get_coin_info<ADA>()), false);

      test::return_shared(dnr_storage);
      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(account_storage);
      test::return_shared(whirpool_storage); 
      test::return_shared(oracle_storage); 
    };
    test::end(scenario);
  }

  #[test]
  #[expected_failure(abort_code = whirpool::ERROR_MARKET_EXIT_LOAN_OPEN)]
  fun test_fail_exit_market_open_loan() {
    let scenario = scenario();

    let test = &mut scenario;

    init_test(test);

    let (alice, _) = people();

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
        mint<BTC>(5, BTC_DECIMALS, ctx(test)),
        ctx(test)
      ));

      whirpool::enter_market<BTC>(&mut account_storage, ctx(test));

      let user_markets_in = whirpool::get_user_markets_in(&account_storage, alice);

      assert_eq(vector::contains(user_markets_in, &get_coin_info<BTC>()), true);

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

      let (coin_btc, coin_ipx) = whirpool::borrow<BTC>(
        &mut whirpool_storage,
        &mut account_storage,
        &interest_rate_model_storage,
        &mut ipx_storage,
        &dnr_storage,
        &oracle_storage,
        (BTC_DECIMALS_FACTOR as u64),
        ctx(test)
       );

      burn(coin_btc);
      burn(coin_ipx);

      whirpool::exit_market<BTC>(
        &mut whirpool_storage,
        &mut account_storage,
        &interest_rate_model_storage,
        &dnr_storage,
        &oracle_storage,
        ctx(test)
      );

      test::return_shared(dnr_storage);
      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(account_storage);
      test::return_shared(whirpool_storage); 
      test::return_shared(oracle_storage); 
    };
    test::end(scenario);
  }

  #[test]
  #[expected_failure(abort_code = whirpool::ERROR_USER_IS_INSOLVENT)]
  fun test_fail_exit_market_insolvent() {
    let scenario = scenario();

    let test = &mut scenario;

    init_test(test);

    let (alice, _) = people();

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

      burn(whirpool::deposit<ADA>(
        &mut whirpool_storage,
        &mut account_storage,
        &interest_rate_model_storage,
        &mut ipx_storage,
        &dnr_storage,
        mint<ADA>(500000, ADA_DECIMALS, ctx(test)),
        ctx(test)
      ));

      whirpool::enter_market<BTC>(&mut account_storage, ctx(test));
      whirpool::enter_market<ADA>(&mut account_storage, ctx(test));

      let user_markets_in = whirpool::get_user_markets_in(&account_storage, alice);

      assert_eq(vector::contains(user_markets_in, &get_coin_info<BTC>()), true);
      assert_eq(vector::contains(user_markets_in, &get_coin_info<ADA>()), true);

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

      let (coin_btc, coin_ipx) = whirpool::borrow<BTC>(
        &mut whirpool_storage,
        &mut account_storage,
        &interest_rate_model_storage,
        &mut ipx_storage,
        &dnr_storage,
        &oracle_storage,
        (8 * BTC_DECIMALS_FACTOR as u64),
        ctx(test)
       );

      burn(coin_btc);
      burn(coin_ipx);

      whirpool::exit_market<ADA>(
        &mut whirpool_storage,
        &mut account_storage,
        &interest_rate_model_storage,
        &dnr_storage,
        &oracle_storage,
        ctx(test)
      );

      test::return_shared(dnr_storage);
      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(account_storage);
      test::return_shared(whirpool_storage); 
      test::return_shared(oracle_storage); 
    };
    test::end(scenario);
  }

  #[test]
  fun test_get_account_balances() {
    let scenario = scenario();

    let test = &mut scenario;

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

      whirpool::enter_market<BTC>(&mut account_storage, ctx(test));

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

      burn(whirpool::deposit<ETH>(
        &mut whirpool_storage,
        &mut account_storage,
        &interest_rate_model_storage,
        &mut ipx_storage,
        &dnr_storage,
        mint<ETH>(100, ETH_DECIMALS, ctx(test)),
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

      let (coin_eth, coin_ipx) = whirpool::borrow<ETH>(
        &mut whirpool_storage,
        &mut account_storage,
        &interest_rate_model_storage,
        &mut ipx_storage,
        &dnr_storage,
        &oracle_storage,
        (10 * ETH_DECIMALS_FACTOR as u64),
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

    advance_epoch(test, alice, 10);
    {
      let whirpool_storage = test::take_shared<WhirpoolStorage>(test);
      let account_storage = test::take_shared<AccountStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let dnr_storage = test::take_shared<DineroStorage>(test);

      let borrow_rate_per_epoch = whirpool::get_borrow_rate_per_epoch<ETH>(
        &whirpool_storage,
        &interest_rate_model_storage,
        &dnr_storage
      );

      let borrow_amount = (10 * ETH_DECIMALS_FACTOR as u64);

      let accumulated_borrow_interest_rate = borrow_rate_per_epoch * 10;

      let interest_rate_amount = fmul(borrow_amount, accumulated_borrow_interest_rate);

      let reserve_amount = fmul(accumulated_borrow_interest_rate, INITIAL_RESERVE_FACTOR_MANTISSA);

      let (alice_collateral, alice_borrows) = whirpool::get_account_balances<ETH>(
        &mut whirpool_storage,
        &account_storage,
        &interest_rate_model_storage,
        &dnr_storage,
        alice,
        ctx(test)
      );

      let (bob_collateral, bob_borrows) = whirpool::get_account_balances<ETH>(
        &mut whirpool_storage,
        &account_storage,
        &interest_rate_model_storage,
        &dnr_storage,
        bob,
        ctx(test)
      );

      assert_eq(alice_collateral, 0);
      assert_eq(alice_borrows, borrow_amount + interest_rate_amount);
      assert_eq(bob_collateral, (100 * ETH_DECIMALS_FACTOR as u64) + interest_rate_amount - reserve_amount);
      assert_eq(bob_borrows, 0);

      test::return_shared(dnr_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(account_storage);
      test::return_shared(whirpool_storage); 
    };

    test::end(scenario);
  }

  #[test]
  fun test_set_interest_rate_data() {
    let scenario = scenario();

    let test = &mut scenario;

    init_test(test);

    let (alice, _) = people();
    next_tx(test, alice);
    {
      let whirpool_storage = test::take_shared<WhirpoolStorage>(test);
      let account_storage = test::take_shared<AccountStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let dnr_storage = test::take_shared<DineroStorage>(test);
      let whirpool_admin_cap = test::take_from_address<WhirpoolAdminCap>(test, alice);

      whirpool::set_interest_rate_data<BTC>(
        &whirpool_admin_cap,
        &mut whirpool_storage,
        &mut interest_rate_model_storage,
        &dnr_storage,
        1000000000,
        2000000000,
        3000000000,
        50000000000,
        ctx(test)
      );

      let (base, multiplier, jump, kink) = model::get_interest_rate_data<BTC>(&interest_rate_model_storage);

      let epochs_per_year = model::get_epochs_per_year();

      assert_eq(base, 1000000000 / epochs_per_year);
      assert_eq(multiplier, 2000000000 / epochs_per_year);
      assert_eq(jump, 3000000000 / epochs_per_year);
      assert_eq(kink, 50000000000);

      test::return_to_address(alice, whirpool_admin_cap);
      test::return_shared(dnr_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(account_storage);
      test::return_shared(whirpool_storage);
    };
    test::end(scenario);
  }

  #[test]
  fun test_set_update_liquidation() {
    let scenario = scenario();

    let test = &mut scenario;

    init_test(test);

    let (alice, _) = people();
    next_tx(test, alice);
    {
      let whirpool_storage = test::take_shared<WhirpoolStorage>(test);
      let whirpool_admin_cap = test::take_from_address<WhirpoolAdminCap>(test, alice);

      whirpool::update_liquidation<BTC>(
        &whirpool_admin_cap,
        &mut whirpool_storage,
        500, 
        300
      );

      let (penalty_fee, protocol_fee) = whirpool::get_liquidation_info<BTC>(&whirpool_storage);

      assert_eq(penalty_fee, 500);
      assert_eq(protocol_fee, 300);

      test::return_to_address(alice, whirpool_admin_cap);
      test::return_shared(whirpool_storage);
    };
    test::end(scenario);
  }

  #[test]
  fun test_pause() {
    let scenario = scenario();

    let test = &mut scenario;

    init_test(test);

    let (alice, _) = people();
    next_tx(test, alice);
    {
      let whirpool_storage = test::take_shared<WhirpoolStorage>(test);
      let whirpool_admin_cap = test::take_from_address<WhirpoolAdminCap>(test, alice);

      whirpool::pause_market<BTC>(
        &whirpool_admin_cap,
        &mut whirpool_storage
      );

      let paused = whirpool::is_market_paused<BTC>(&whirpool_storage);

      assert_eq(paused, true);

      whirpool::unpause_market<BTC>(
        &whirpool_admin_cap,
        &mut whirpool_storage
      );

      let paused = whirpool::is_market_paused<BTC>(&whirpool_storage);

      assert_eq(paused, false);

      test::return_to_address(alice, whirpool_admin_cap);
      test::return_shared(whirpool_storage);    
    };
    test::end(scenario);
  }

    #[test]
    fun test_set_borrow_cap() {
    let scenario = scenario();

    let test = &mut scenario;

    init_test(test);

    let (alice, _) = people();
    next_tx(test, alice);
    {
      let whirpool_storage = test::take_shared<WhirpoolStorage>(test);
      let whirpool_admin_cap = test::take_from_address<WhirpoolAdminCap>(test, alice);

      whirpool::set_borrow_cap<BTC>(
        &whirpool_admin_cap,
        &mut whirpool_storage,
        2
      );

      let (_, _, borrow_cap, _, _, _, _, _, _, _, _, _, _, _, _) = whirpool::get_market_info<BTC>(&whirpool_storage);

      assert_eq(borrow_cap, 2);

      test::return_to_address(alice, whirpool_admin_cap);
      test::return_shared(whirpool_storage);    
    };
    test::end(scenario);
  }

  #[test]
  fun test_update_reserve_factor() {
    let scenario = scenario();

    let test = &mut scenario;

    init_test(test);

    let (alice, _) = people();
    advance_epoch(test, alice, 5);
    next_tx(test, alice);
    {
      let whirpool_storage = test::take_shared<WhirpoolStorage>(test);
      let account_storage = test::take_shared<AccountStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let dnr_storage = test::take_shared<DineroStorage>(test);
      let whirpool_admin_cap = test::take_from_address<WhirpoolAdminCap>(test, alice);

      whirpool::update_reserve_factor<BTC>(
        &whirpool_admin_cap,
        &mut whirpool_storage,
        &mut interest_rate_model_storage,
        &dnr_storage,
        10000,
        ctx(test)
      );

      let (_, accrued_epoch, _, _, _, _, _, reserve_factor, _, _, _, _, _, _, _) = whirpool::get_market_info<BTC>(&whirpool_storage);

      assert_eq(accrued_epoch, 5);
      assert_eq(reserve_factor, 10000);

      test::return_to_address(alice, whirpool_admin_cap);
      test::return_shared(dnr_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(account_storage);
      test::return_shared(whirpool_storage);
    };
    test::end(scenario);
  }

  #[test]
  fun test_withdraw_reserves() {
    let scenario = scenario();

    let test = &mut scenario;

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

      whirpool::enter_market<BTC>(&mut account_storage, ctx(test));

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

      burn(whirpool::deposit<ETH>(
        &mut whirpool_storage,
        &mut account_storage,
        &interest_rate_model_storage,
        &mut ipx_storage,
        &dnr_storage,
        mint<ETH>(100, ETH_DECIMALS, ctx(test)),
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

      let borrow_value = (10 * ETH_DECIMALS_FACTOR as u64);

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

    advance_epoch(test, alice, 10);
    next_tx(test, alice);
    {
      let whirpool_storage = test::take_shared<WhirpoolStorage>(test);
      let account_storage = test::take_shared<AccountStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);
      let dnr_storage = test::take_shared<DineroStorage>(test);
      let oracle_storage = test::take_shared<OracleStorage>(test);
      let whirpool_admin_cap = test::take_from_address<WhirpoolAdminCap>(test, alice);

      let borrow_rate_per_epoch = whirpool::get_borrow_rate_per_epoch<ETH>(
        &whirpool_storage,
        &interest_rate_model_storage,
        &dnr_storage
      );

      let borrow_amount = (10 * ETH_DECIMALS_FACTOR as u64);

      let accumulated_borrow_interest_rate = borrow_rate_per_epoch * 10;

      let interest_rate_amount = fmul(borrow_amount, accumulated_borrow_interest_rate);

      let reserve_amount = fmul(interest_rate_amount, INITIAL_RESERVE_FACTOR_MANTISSA);

      whirpool::withdraw_reserves<ETH>(
        &whirpool_admin_cap,
        &mut whirpool_storage,
        &interest_rate_model_storage,
        &dnr_storage,
        reserve_amount,
        ctx(test)
      );

      let (total_reserves, accrued_epoch, _, _, _, _, _, _, _, _, _, _, _, _, _) = whirpool::get_market_info<ETH>(&whirpool_storage);

      assert_eq(accrued_epoch, 10);
      assert_eq(total_reserves, 0);
    
      test::return_to_address(alice, whirpool_admin_cap);
      test::return_shared(dnr_storage);
      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(account_storage);
      test::return_shared(whirpool_storage); 
      test::return_shared(oracle_storage);  
    };

    test::end(scenario);
  }

  #[test]
  #[expected_failure(abort_code = whirpool::ERROR_NOT_ENOUGH_CASH_TO_WITHDRAW)]
  fun test_fail_withdraw_reserves_no_cash() {
    let scenario = scenario();

    let test = &mut scenario;

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

      whirpool::enter_market<BTC>(&mut account_storage, ctx(test));

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

      burn(whirpool::deposit<ETH>(
        &mut whirpool_storage,
        &mut account_storage,
        &interest_rate_model_storage,
        &mut ipx_storage,
        &dnr_storage,
        mint<ETH>(10, ETH_DECIMALS, ctx(test)),
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

      let borrow_value = (10 * ETH_DECIMALS_FACTOR as u64);

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

    advance_epoch(test, alice, 10);
    next_tx(test, alice);
    {
      let whirpool_storage = test::take_shared<WhirpoolStorage>(test);
      let account_storage = test::take_shared<AccountStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);
      let dnr_storage = test::take_shared<DineroStorage>(test);
      let oracle_storage = test::take_shared<OracleStorage>(test);
      let whirpool_admin_cap = test::take_from_address<WhirpoolAdminCap>(test, alice);

      let borrow_rate_per_epoch = whirpool::get_borrow_rate_per_epoch<ETH>(
        &whirpool_storage,
        &interest_rate_model_storage,
        &dnr_storage
      );

      let borrow_amount = (10 * ETH_DECIMALS_FACTOR as u64);

      let accumulated_borrow_interest_rate = borrow_rate_per_epoch * 10;

      let interest_rate_amount = fmul(borrow_amount, accumulated_borrow_interest_rate);

      let reserve_amount = fmul(interest_rate_amount, INITIAL_RESERVE_FACTOR_MANTISSA);

      whirpool::withdraw_reserves<ETH>(
        &whirpool_admin_cap,
        &mut whirpool_storage,
        &interest_rate_model_storage,
        &dnr_storage,
        reserve_amount,
        ctx(test)
      );
    
      test::return_to_address(alice, whirpool_admin_cap);
      test::return_shared(dnr_storage);
      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(account_storage);
      test::return_shared(whirpool_storage); 
      test::return_shared(oracle_storage);  
    };

    test::end(scenario);
  }

  #[test]
  #[expected_failure(abort_code = whirpool::ERROR_NOT_ENOUGH_RESERVES)]
  fun test_fail_withdraw_reserves_not_enough_reserves() {
    let scenario = scenario();

    let test = &mut scenario;

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

      whirpool::enter_market<BTC>(&mut account_storage, ctx(test));

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

      burn(whirpool::deposit<ETH>(
        &mut whirpool_storage,
        &mut account_storage,
        &interest_rate_model_storage,
        &mut ipx_storage,
        &dnr_storage,
        mint<ETH>(100, ETH_DECIMALS, ctx(test)),
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

      let borrow_value = (10 * ETH_DECIMALS_FACTOR as u64);

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

    advance_epoch(test, alice, 10);
    next_tx(test, alice);
    {
      let whirpool_storage = test::take_shared<WhirpoolStorage>(test);
      let account_storage = test::take_shared<AccountStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);
      let dnr_storage = test::take_shared<DineroStorage>(test);
      let oracle_storage = test::take_shared<OracleStorage>(test);
      let whirpool_admin_cap = test::take_from_address<WhirpoolAdminCap>(test, alice);

      let borrow_rate_per_epoch = whirpool::get_borrow_rate_per_epoch<ETH>(
        &whirpool_storage,
        &interest_rate_model_storage,
        &dnr_storage
      );

      let borrow_amount = (10 * ETH_DECIMALS_FACTOR as u64);

      let accumulated_borrow_interest_rate = borrow_rate_per_epoch * 10;

      let interest_rate_amount = fmul(borrow_amount, accumulated_borrow_interest_rate);

      let reserve_amount = fmul(interest_rate_amount, INITIAL_RESERVE_FACTOR_MANTISSA);

      whirpool::withdraw_reserves<ETH>(
        &whirpool_admin_cap,
        &mut whirpool_storage,
        &interest_rate_model_storage,
        &dnr_storage,
        reserve_amount + 1,
        ctx(test)
      );
    
      test::return_to_address(alice, whirpool_admin_cap);
      test::return_shared(dnr_storage);
      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(account_storage);
      test::return_shared(whirpool_storage); 
      test::return_shared(oracle_storage);  
    };

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

