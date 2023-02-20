#[test_only]
module interest_protocol::whirpool_test {

  use sui::test_scenario::{Self as test, Scenario, next_tx, ctx};
  use sui::coin::{destroy_for_testing as burn};
  use sui::math;

  use interest_protocol::whirpool::{Self, WhirpoolAdminCap, WhirpoolStorage, AccountStorage};
  use interest_protocol::ipx::{Self, IPXStorage};
  use interest_protocol::dnr::{Self, DineroStorage};
  use interest_protocol::oracle::{Self, OracleStorage, OracleAdminCap};
  use interest_protocol::interest_rate_model::{Self as model, InterestRateModelStorage};
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

      assert!(burn(coin_ipx) == 0, 0);
      assert!(collateral == 10 * math::pow(10, BTC_DECIMALS), 0);
      assert!(loan == 0, 0);
      assert!(collateral_rewards_paid == 0, 0);
      assert!(loan_rewards_paid == 0, 0);

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

      let collateral_rewards_per_share = (((((100 * IPX_DECIMALS_FACTOR as u256) *  10 * 500 )/ 2100) / 2) * BTC_DECIMALS_FACTOR / (10 * BTC_DECIMALS_FACTOR as u256));

      assert!((burn(coin_ipx) as u256) == collateral_rewards_per_share * (10 * BTC_DECIMALS_FACTOR as u256) / BTC_DECIMALS_FACTOR, 0);
      assert!(collateral == 15 * math::pow(10, BTC_DECIMALS), 0);
      assert!(loan == 0, 0);
      assert!(collateral_rewards_paid == (collateral_rewards_per_share * (15 * BTC_DECIMALS_FACTOR)) / BTC_DECIMALS_FACTOR, 0);
      assert!(loan_rewards_paid == 0, 0);

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

      let collateral_rewards_per_share = (((((100 * IPX_DECIMALS_FACTOR as u256) *  5 * 500 ) / 2100) / 2) * BTC_DECIMALS_FACTOR / (15 * BTC_DECIMALS_FACTOR as u256)) + prev_collateral_rewards_per_share;

      assert!((burn(coin_ipx) as u256) == 0, 0);
      assert!((collateral as u256) == 7 * BTC_DECIMALS_FACTOR, 0);
      assert!(loan == 0, 0);
      assert!(collateral_rewards_paid == (collateral_rewards_per_share * (7 * BTC_DECIMALS_FACTOR)) / BTC_DECIMALS_FACTOR, 0);
      assert!(loan_rewards_paid == 0, 0);

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

      assert!(burn(coin_btc) == (3 * BTC_DECIMALS_FACTOR as u64), 0);
      assert!(burn(coin_ipx) == 0, 0);
      assert!(collateral == (7 * BTC_DECIMALS_FACTOR as u64), 0);
      assert!(loan == 0, 0);
      assert!(collateral_rewards_paid == 0, 0);
      assert!(loan_rewards_paid == 0, 0);

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

      let collateral_rewards_per_share = ((6 * (100 * IPX_DECIMALS_FACTOR) * 500) / 2100/ 2) * BTC_DECIMALS_FACTOR / (7 * BTC_DECIMALS_FACTOR); 

      assert!(burn(coin_btc) == (4 * BTC_DECIMALS_FACTOR as u64), 0);
      assert!((burn(coin_ipx) as u256) == collateral_rewards_per_share * (7 * BTC_DECIMALS_FACTOR)/ BTC_DECIMALS_FACTOR, 0);
      assert!(collateral == (3 * BTC_DECIMALS_FACTOR as u64), 0);
      assert!(loan == 0, 0);
      assert!(collateral_rewards_paid == collateral_rewards_per_share * (3 * BTC_DECIMALS_FACTOR) / BTC_DECIMALS_FACTOR, 0);
      assert!(loan_rewards_paid == 0, 0);

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

      let collateral_rewards_per_share = ((10 * (100 * IPX_DECIMALS_FACTOR) * 500) / 2100/ 2) * BTC_DECIMALS_FACTOR / (15 * BTC_DECIMALS_FACTOR) + prev_collateral_rewards_per_share; 

      assert!(burn(coin_btc) == (5 * BTC_DECIMALS_FACTOR as u64), 0);
      assert!((burn(coin_ipx) as u256) == (collateral_rewards_per_share * (12 * BTC_DECIMALS_FACTOR)/ BTC_DECIMALS_FACTOR) - prev_collateral_rewards_paid, 0);
      assert!(collateral == (7 * BTC_DECIMALS_FACTOR as u64), 0);
      assert!(loan == 0, 0);
      assert!(collateral_rewards_paid == collateral_rewards_per_share * (7 * BTC_DECIMALS_FACTOR) / BTC_DECIMALS_FACTOR, 0);
      assert!(loan_rewards_paid == 0, 0);

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

      assert!(burn(coin_eth)  == borrow_value, 0);
      assert!(burn(coin_ipx) == 0, 0); 

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
}

