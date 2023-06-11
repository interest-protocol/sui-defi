#[test_only]
module money_market::ipx_money_market_test {
  use std::vector;

  use sui::test_scenario::{Self as test, Scenario, next_tx, ctx};
  use sui::test_utils::{assert_eq};
  use sui::coin::{burn_for_testing as burn, CoinMetadata};
  use sui::math;
  use sui::clock;

  use money_market::ipx_money_market::{Self as money_market, MoneyMarketAdminCap, MoneyMarketStorage};
  use money_market::interest_rate_model::{Self as model, InterestRateModelStorage};
 
  use oracle::ipx_oracle::{get_price_for_testing, Price as PricePotato};

  use ipx::ipx::{Self, IPXStorage, IPXAdminCap};
 
  use sui_dollar::suid::{Self, SUID, SuiDollarStorage, SuiDollarAdminCap};
 
  use library::math::{d_fmul, d_fmul_u256};
  use library::utils::{get_type_name_string};
  use library::test_utils::{people,  mint, scenario};
  use library::ada::{Self, ADA};
  use library::eth::{Self, ETH};
  use library::btc::{Self, BTC};

  const ONE_PERCENT: u256 = 10000000000000000;
  const TWO_PERCENT: u256 = 20000000000000000;
  const KINK: u256 = 700000000000000000; // 70%
  const INITIAL_BTC_PRICE: u256 = 20000000000000000000000; // 20k - 18 decimals
  const INITIAL_ETH_PRICE: u256 = 1400000000000000000000; // 1400 - 18 decimals
  const INITIAL_ADA_PRICE: u256 = 3000000000000000000; // 30 cents - 18 decimals
  const SUID_PRICE: u64 = 1000000000000000000; // 1 USD
  const BTC_BORROW_CAP: u64 = 100000000000; // 100 BTC - 9 decimals
  const ETH_BORROW_CAP: u64 = 50000000000; // 500 ETH 8 decimals
  const ADA_BORROW_CAP: u64 = 100000000000000; // 10M 7 decimals
  const SUID_BORROW_CAP: u64 = 150000000000000; // 100k 9 decimals
  const BTC_DECIMALS: u8 = 9;
  const ETH_DECIMALS: u8 = 8;
  const ADA_DECIMALS: u8 = 7;
  const SUID_DECIMALS: u8 = 9;
  const IPX_DECIMALS_FACTOR: u256 = 1000000000;
  const BTC_DECIMALS_FACTOR: u256 = 1000000000;
  const ETH_DECIMALS_FACTOR: u256 = 100000000;
  const ADA_DECIMALS_FACTOR: u256 = 10000000;
  const SUID_DECIMALS_FACTOR: u256 = 1000000000;
  const INITIAL_RESERVE_FACTOR_MANTISSA: u64 = 200000000000000000; // 0.2e18 or 20%
  const MS_PER_YEAR: u256 = 31536000000; 
  // ATTENTION This needs to be updated when the module constant is updated.
  const INITIAL_IPX_PER_MS: u256 = 1268391; // 40M IPX per year

  public fun init_test(test: &mut Scenario) {
    let (alice, _) = people();

    // Init modules
    next_tx(test, alice);
    {
      money_market::init_for_testing(ctx(test));
      ipx::init_for_testing(ctx(test));
      suid::init_for_testing(ctx(test));
      model::init_for_testing(ctx(test));
      ada::init_for_testing(ctx(test));
      btc::init_for_testing(ctx(test));
      eth::init_for_testing(ctx(test));
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
        ONE_PERCENT + TWO_PERCENT, // jump
        KINK,
        ctx(test)
      );

      // ETH
      model::set_interest_rate_data_test<ETH>(
        &mut storage,
        ONE_PERCENT * 2, // base 
        TWO_PERCENT, // multiplier
        TWO_PERCENT * 3, // jump
        KINK,
        ctx(test)
      );

       // ADA
      model::set_interest_rate_data_test<ADA>(
        &mut storage,
        ONE_PERCENT, // base 
        TWO_PERCENT + ONE_PERCENT, // multiplier
        (TWO_PERCENT + ONE_PERCENT) * 3, // jump
        KINK,
        ctx(test)
      );
      test::return_shared(storage);
    };

    next_tx(test, alice);
    {
      let money_market_storage = test::take_shared<MoneyMarketStorage>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);
      let suid_storage = test::take_shared<SuiDollarStorage>(test);      
      let ipx_admin_cap = test::take_from_address<IPXAdminCap>(test, alice);
      let suid_admin_cap = test::take_from_address<SuiDollarAdminCap>(test, alice);   

      let id = money_market::get_publisher_id(&money_market_storage);

      ipx::add_minter(
        &ipx_admin_cap,
        &mut ipx_storage,
        id
      );

      suid::add_minter(
        &suid_admin_cap,
        &mut suid_storage,
        id
      );

      test::return_to_address(alice, ipx_admin_cap);
      test::return_to_address(alice, suid_admin_cap);
      test::return_shared(money_market_storage); 
      test::return_shared(suid_storage);
      test::return_shared(ipx_storage);   
    };

    let clock_object = clock::create_for_testing(ctx(test));

    // Add Markets
    next_tx(test, alice);
    {
      let money_market_admin_cap = test::take_from_address<MoneyMarketAdminCap>(test, alice);
      let money_market_storage = test::take_shared<MoneyMarketStorage>(test);
      let btc_coin_metadata = test::take_shared<CoinMetadata<BTC>>(test);
      let eth_coin_metadata = test::take_shared<CoinMetadata<ETH>>(test);
      let ada_coin_metadata = test::take_shared<CoinMetadata<ADA>>(test);
      let suid_coin_metadata = test::take_immutable<CoinMetadata<SUID>>(test);

      money_market::create_market<BTC>(
        &money_market_admin_cap,
        &mut money_market_storage,
        &clock_object,
        &btc_coin_metadata,
        BTC_BORROW_CAP,
        BTC_BORROW_CAP * 2,
        700000000000000000, // 70% ltv
        500, // allocation points
        50000000000000000, // 5% penalty fee
        200000000000000000, // 20% protocol fee
        true,
        ctx(test)
      );

      money_market::create_market<ETH>(
        &money_market_admin_cap,
        &mut money_market_storage,
        &clock_object,
        &eth_coin_metadata,
        ETH_BORROW_CAP,
        ETH_BORROW_CAP * 2,
        650000000000000000, // 65% ltv
        700, // allocation points
        70000000000000000, // 7% penalty fee
        100000000000000000, // 10% protocol fee
        true,
        ctx(test)
      );


      money_market::create_market<ADA>(
        &money_market_admin_cap,
        &mut money_market_storage,
        &clock_object,
        &ada_coin_metadata,
        ADA_BORROW_CAP,
        ADA_BORROW_CAP * 2,
        500000000000000000, // 50% ltv
        900, // allocation points
        100000000000000000, // 10% penalty fee
        200000000000000000, // 20% protocol fee
        true,
        ctx(test)
      );
  
      money_market::create_market<SUID>(
        &money_market_admin_cap,
        &mut money_market_storage,
        &clock_object,
        &suid_coin_metadata,
        SUID_BORROW_CAP,
        0, // cannot be as collateral
        0, // 50% ltv
        500, // allocation points
        100000000000000000, // 10% penalty fee
        200000000000000000, // 20% protocol fee
        false,
        ctx(test)
      );
      
      test::return_to_address(alice, money_market_admin_cap);
      test::return_shared(btc_coin_metadata);
      test::return_shared(eth_coin_metadata);
      test::return_shared(ada_coin_metadata);
      test::return_immutable(suid_coin_metadata);
      test::return_shared(money_market_storage);
    };

    clock::destroy_for_testing(clock_object);
  }

  fun test_deposit_(test: &mut Scenario) {
    init_test(test);

    let (alice, bob) = people();

    let clock_object = clock::create_for_testing(ctx(test));

    next_tx(test, alice);
    {
      let money_market_storage = test::take_shared<MoneyMarketStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);

      let coin_ipx = money_market::deposit<BTC>(
        &mut money_market_storage,
        &interest_rate_model_storage,
        &mut ipx_storage,
        &clock_object,
        mint<BTC>(10, BTC_DECIMALS, ctx(test)),
        ctx(test)
      );

      let (collateral, loan, collateral_rewards_paid, loan_rewards_paid) = money_market::get_account_info<BTC>(&money_market_storage, alice);

      assert_eq(burn(coin_ipx), 0);
      assert_eq(collateral, 10 * math::pow(10, BTC_DECIMALS));
      assert_eq(loan, 0);
      assert_eq(collateral_rewards_paid, 0);
      assert_eq(loan_rewards_paid, 0);

      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(money_market_storage);
    };

    next_tx(test, alice);
    {
      let money_market_storage = test::take_shared<MoneyMarketStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);

      clock::increment_for_testing(&mut clock_object, 12000);

      let coin_ipx = money_market::deposit<BTC>(
        &mut money_market_storage,
        &interest_rate_model_storage,
        &mut ipx_storage,
        &clock_object,
        mint<BTC>(5, BTC_DECIMALS, ctx(test)),
        ctx(test)
      );

      let (collateral, loan, collateral_rewards_paid, loan_rewards_paid) = money_market::get_account_info<BTC>(&money_market_storage, alice);

      let collateral_rewards_per_share = calculate_btc_market_rewards(12000, 10 * BTC_DECIMALS_FACTOR);

      assert_eq((burn(coin_ipx) as u256), collateral_rewards_per_share * (10 * BTC_DECIMALS_FACTOR as u256) / BTC_DECIMALS_FACTOR);
      assert_eq(collateral, 15 * math::pow(10, BTC_DECIMALS));
      assert_eq(loan, 0);
      assert_eq(collateral_rewards_paid, (collateral_rewards_per_share * (15 * BTC_DECIMALS_FACTOR)) / BTC_DECIMALS_FACTOR);
      assert_eq(loan_rewards_paid, 0);

      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(money_market_storage);
    };

    next_tx(test, bob);
    {
      let money_market_storage = test::take_shared<MoneyMarketStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);

      clock::increment_for_testing(&mut clock_object, 20000);

      let (_, _, _, _, _, _, _, _, _, prev_collateral_rewards_per_share, _, _, _, _, _, _) = money_market::get_market_info<BTC>(&money_market_storage);

      let coin_ipx = money_market::deposit<BTC>(
        &mut money_market_storage,
        &interest_rate_model_storage,
        &mut ipx_storage,
        &clock_object,
        mint<BTC>(7, BTC_DECIMALS, ctx(test)),
        ctx(test)
      );

      let (collateral, loan, collateral_rewards_paid, loan_rewards_paid) = money_market::get_account_info<BTC>(&money_market_storage, bob);

      let collateral_rewards_per_share = calculate_btc_market_rewards(20000, 15 * BTC_DECIMALS_FACTOR) + prev_collateral_rewards_per_share;

      assert_eq((burn(coin_ipx) as u256), 0);
      assert_eq((collateral as u256), 7 * BTC_DECIMALS_FACTOR);
      assert_eq(loan, 0);
      assert_eq(collateral_rewards_paid, (collateral_rewards_per_share * (7 * BTC_DECIMALS_FACTOR)) / BTC_DECIMALS_FACTOR);
      assert_eq(loan_rewards_paid, 0);

      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(money_market_storage);
    };    

    clock::destroy_for_testing(clock_object);
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
    let clock_object = clock::create_for_testing(ctx(test));

    next_tx(test, alice);
    {
      let money_market_storage = test::take_shared<MoneyMarketStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);
      let suid_storage = test::take_shared<SuiDollarStorage>(test);

     burn(money_market::deposit<BTC>(
        &mut money_market_storage,
        &interest_rate_model_storage,
        &mut ipx_storage,
        &clock_object,
        mint<BTC>(10, BTC_DECIMALS, ctx(test)),
        ctx(test)
     ));

      let (coin_btc, coin_ipx) = money_market::withdraw<BTC>(
        &mut money_market_storage, 
        &interest_rate_model_storage, 
        &mut ipx_storage, 
        get_all_prices_potatoes(),
        &clock_object,
        (3 * BTC_DECIMALS_FACTOR as u64), 
        ctx(test)
      );

      let (collateral, loan, collateral_rewards_paid, loan_rewards_paid) = money_market::get_account_info<BTC>(&money_market_storage, alice);

      assert_eq(burn(coin_btc), (3 * BTC_DECIMALS_FACTOR as u64));
      assert_eq(burn(coin_ipx), 0);
      assert_eq(collateral, (7 * BTC_DECIMALS_FACTOR as u64));
      assert_eq(loan, 0);
      assert_eq(collateral_rewards_paid, 0);
      assert_eq(loan_rewards_paid, 0);

      test::return_shared(suid_storage);
      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(money_market_storage); 
    };

    next_tx(test, alice);
    {
      let money_market_storage = test::take_shared<MoneyMarketStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);
      let suid_storage = test::take_shared<SuiDollarStorage>(test);

      clock::increment_for_testing(&mut clock_object, 35000);

      let (coin_btc, coin_ipx) = money_market::withdraw<BTC>(
        &mut money_market_storage, 
        &interest_rate_model_storage, 
        &mut ipx_storage, 
        get_all_prices_potatoes(),
        &clock_object,
        (4 * BTC_DECIMALS_FACTOR as u64), 
        ctx(test)
      );

      let (collateral, loan, collateral_rewards_paid, loan_rewards_paid) = money_market::get_account_info<BTC>(&money_market_storage, alice);

      let collateral_rewards_per_share = calculate_btc_market_rewards(35000, 7 * BTC_DECIMALS_FACTOR);

      assert_eq(burn(coin_btc), (4 * BTC_DECIMALS_FACTOR as u64));
      assert_eq((burn(coin_ipx) as u256), collateral_rewards_per_share * (7 * BTC_DECIMALS_FACTOR)/ BTC_DECIMALS_FACTOR);
      assert_eq(collateral, (3 * BTC_DECIMALS_FACTOR as u64));
      assert_eq(loan, 0);
      assert_eq(collateral_rewards_paid, collateral_rewards_per_share * (3 * BTC_DECIMALS_FACTOR) / BTC_DECIMALS_FACTOR);
      assert_eq(loan_rewards_paid, 0);

      test::return_shared(suid_storage);
      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(money_market_storage);        
    };

    next_tx(test, bob);
    {
      let money_market_storage = test::take_shared<MoneyMarketStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);

      burn(money_market::deposit<BTC>(
        &mut money_market_storage,
        &interest_rate_model_storage,
        &mut ipx_storage,
        &clock_object,
        mint<BTC>(12, BTC_DECIMALS, ctx(test)),
        ctx(test)
      ));

      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(money_market_storage); 
    };

    next_tx(test, bob);
    {
      let money_market_storage = test::take_shared<MoneyMarketStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);
      let suid_storage = test::take_shared<SuiDollarStorage>(test);

      let (_, _, _, _, _, _, _, _, _, prev_collateral_rewards_per_share, _, _, _, _, _, _) = money_market::get_market_info<BTC>(&money_market_storage);

      let (_, _, prev_collateral_rewards_paid, _) = money_market::get_account_info<BTC>(&money_market_storage, bob);

      clock::increment_for_testing(&mut clock_object, 27000);

      let (coin_btc, coin_ipx) = money_market::withdraw<BTC>(
        &mut money_market_storage, 
        &interest_rate_model_storage, 
        &mut ipx_storage, 
        get_all_prices_potatoes(),
        &clock_object,
        (5 * BTC_DECIMALS_FACTOR as u64), 
        ctx(test)
      );

      let (collateral, loan, collateral_rewards_paid, loan_rewards_paid) = money_market::get_account_info<BTC>(&money_market_storage, bob);

      let collateral_rewards_per_share = calculate_btc_market_rewards(27000, 15 * BTC_DECIMALS_FACTOR) + prev_collateral_rewards_per_share; 

      assert_eq(burn(coin_btc), (5 * BTC_DECIMALS_FACTOR as u64));
      assert_eq((burn(coin_ipx) as u256), (collateral_rewards_per_share * (12 * BTC_DECIMALS_FACTOR)/ BTC_DECIMALS_FACTOR) - prev_collateral_rewards_paid);
      assert_eq(collateral, (7 * BTC_DECIMALS_FACTOR as u64));
      assert_eq(loan, 0);
      assert_eq(collateral_rewards_paid, collateral_rewards_per_share * (7 * BTC_DECIMALS_FACTOR) / BTC_DECIMALS_FACTOR);
      assert_eq(loan_rewards_paid, 0);

      test::return_shared(suid_storage);
      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(money_market_storage);  
    };

    clock::destroy_for_testing(clock_object);
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
    let clock_object = clock::create_for_testing(ctx(test));

    next_tx(test, alice);
    {
      let money_market_storage = test::take_shared<MoneyMarketStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);

      burn(money_market::deposit<BTC>(
        &mut money_market_storage,
        &interest_rate_model_storage,
        &mut ipx_storage,
        &clock_object,
        mint<BTC>(10, BTC_DECIMALS, ctx(test)),
        ctx(test)
       ));

      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(money_market_storage); 
    };

    next_tx(test, bob);
    {
      let money_market_storage = test::take_shared<MoneyMarketStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);
      let suid_storage = test::take_shared<SuiDollarStorage>(test);

      burn(money_market::deposit<BTC>(
        &mut money_market_storage,
        &interest_rate_model_storage,
        &mut ipx_storage,
        &clock_object,
        mint<BTC>(10, BTC_DECIMALS, ctx(test)),
        ctx(test)
       ));

      burn(money_market::deposit<ETH>(
        &mut money_market_storage,
        &interest_rate_model_storage,
        &mut ipx_storage,
        &clock_object,
        mint<ETH>(300, ETH_DECIMALS, ctx(test)),
        ctx(test)
       ));

      test::return_shared(suid_storage);
      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(money_market_storage); 
    };

    next_tx(test, alice);
    {
      let money_market_storage = test::take_shared<MoneyMarketStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);
      let suid_storage = test::take_shared<SuiDollarStorage>(test);

      let borrow_value = (99 * ETH_DECIMALS_FACTOR as u64);

      money_market::enter_market<BTC>(&mut money_market_storage, ctx(test));

      let (coin_eth, coin_ipx) = money_market::borrow<ETH>(
        &mut money_market_storage,
        &interest_rate_model_storage,
        &mut ipx_storage,
        get_all_prices_potatoes(),
        &clock_object,
        borrow_value,
        ctx(test)
       );

      let (collateral, loan, collateral_rewards_paid, loan_rewards_paid) = money_market::get_account_info<ETH>(&money_market_storage, alice);
 
      assert_eq(burn(coin_eth), borrow_value);
      assert_eq(burn(coin_ipx), 0); 
      assert_eq(collateral, 0);
      assert_eq(collateral_rewards_paid, 0);
      assert_eq(loan, borrow_value);
      assert_eq(loan_rewards_paid, 0);

      test::return_shared(suid_storage);
      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(money_market_storage); 
    };

    next_tx(test, alice);
    {
      let money_market_storage = test::take_shared<MoneyMarketStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);

      clock::increment_for_testing(&mut clock_object, 50000);

      // So we can borrow more
      burn(money_market::deposit<BTC>(
        &mut money_market_storage,
        &interest_rate_model_storage,
        &mut ipx_storage,
        &clock_object,
        mint<BTC>(10, BTC_DECIMALS, ctx(test)),
        ctx(test)
       ));

      let borrow_value = (10 * ETH_DECIMALS_FACTOR as u64);

      let interest_rate_per_ms = money_market::get_borrow_rate_per_ms<ETH>(
        &money_market_storage,
        &interest_rate_model_storage,
      );

      let (_, _, _, _, _, _, _, _, _, _, _, _, _, total_principal, total_borrows, _) = money_market::get_market_info<ETH>(&money_market_storage);

      let accumulated_interest_rate = interest_rate_per_ms * 50000;
      let new_total_borrows = total_borrows + (d_fmul(total_borrows, accumulated_interest_rate) as u64);

      // round up
      let added_principal = ((borrow_value * total_principal) / new_total_borrows) + 1;

      let (coin_eth, coin_ipx) = money_market::borrow<ETH>(
        &mut money_market_storage,
        &interest_rate_model_storage,
        &mut ipx_storage,
        get_all_prices_potatoes(),
        &clock_object,
        borrow_value,
        ctx(test)
       );

      // 5 epoch rewards
      let loan_rewards_per_share = calculate_eth_market_rewards(50000, 99 * ETH_DECIMALS_FACTOR);

      let (collateral, loan, collateral_rewards_paid, loan_rewards_paid) = money_market::get_account_info<ETH>(&money_market_storage, alice);
      let new_principal = 99 * ETH_DECIMALS_FACTOR + (added_principal as u256);

      assert_eq(burn(coin_eth), borrow_value);  
      assert_eq((burn(coin_ipx) as u256), loan_rewards_per_share * 99); 
      assert_eq(collateral, 0);
      assert_eq((loan as u256), new_principal);
      assert_eq(collateral_rewards_paid, 0);
      assert_eq(loan_rewards_paid, loan_rewards_per_share * new_principal / ETH_DECIMALS_FACTOR);

      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(money_market_storage); 
    };

    next_tx(test, alice);
    {
      let money_market_storage = test::take_shared<MoneyMarketStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);

      clock::increment_for_testing(&mut clock_object, 4000000);
      let borrow_value = (5 * ETH_DECIMALS_FACTOR as u64);

      let interest_rate_per_ms = money_market::get_borrow_rate_per_ms<ETH>(
        &money_market_storage,
        &interest_rate_model_storage
      );

      let (_, _, _, _, _, _, _, _, _, _, prev_loan_rewards_per_share, _, _, total_principal, total_borrows, _) = money_market::get_market_info<ETH>(&money_market_storage);

      let accumulated_interest_rate = interest_rate_per_ms * 4000000;
      let new_total_borrows = total_borrows + (d_fmul(total_borrows, accumulated_interest_rate) as u64);

      // round up
      let added_principal = ((borrow_value * total_principal) / new_total_borrows) + 1;

      let (_, prev_loan, _, prev_loan_rewards_paid) = money_market::get_account_info<ETH>(&money_market_storage, alice);

      let (coin_eth, coin_ipx) = money_market::borrow<ETH>(
        &mut money_market_storage,
        &interest_rate_model_storage,
        &mut ipx_storage,
        get_all_prices_potatoes(),
        &clock_object,
        borrow_value,
        ctx(test)
       );

      // 5 epoch rewards
      let loan_rewards_per_share = calculate_eth_market_rewards(4000000, (total_principal as u256)) + prev_loan_rewards_per_share;

      let (collateral, loan, collateral_rewards_paid, loan_rewards_paid) = money_market::get_account_info<ETH>(&money_market_storage, alice);
      let new_principal = prev_loan + added_principal;

      assert_eq(burn(coin_eth), borrow_value);  
      assert_eq((burn(coin_ipx) as u256), (loan_rewards_per_share * (prev_loan as u256) / ETH_DECIMALS_FACTOR) - prev_loan_rewards_paid); 
      assert_eq(collateral, 0);
      assert_eq(loan, new_principal);
      assert_eq(collateral_rewards_paid, 0);
      assert_eq(loan_rewards_paid, loan_rewards_per_share * (new_principal as u256) / ETH_DECIMALS_FACTOR);

      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(money_market_storage); 
    };

    clock::destroy_for_testing(clock_object);
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
    let clock_object = clock::create_for_testing(ctx(test));

    next_tx(test, alice);
    {
      let money_market_storage = test::take_shared<MoneyMarketStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);

      burn(money_market::deposit<BTC>(
        &mut money_market_storage,
        &interest_rate_model_storage,
        &mut ipx_storage,
        &clock_object,
        mint<BTC>(10, BTC_DECIMALS, ctx(test)),
        ctx(test)
       ));

      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(money_market_storage); 
    };

    next_tx(test, bob);
    {
      let money_market_storage = test::take_shared<MoneyMarketStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);

      burn(money_market::deposit<BTC>(
        &mut money_market_storage,
        &interest_rate_model_storage,
        &mut ipx_storage,
        &clock_object,
        mint<BTC>(10, BTC_DECIMALS, ctx(test)),
        ctx(test)
       ));

      burn(money_market::deposit<ETH>(
        &mut money_market_storage,
        &interest_rate_model_storage,
        &mut ipx_storage,
        &clock_object,
        mint<ETH>(300, ETH_DECIMALS, ctx(test)),
        ctx(test)
       ));

      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(money_market_storage); 
    };

    next_tx(test, alice);
    {
      let money_market_storage = test::take_shared<MoneyMarketStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);

      let borrow_value = (50 * ETH_DECIMALS_FACTOR as u64);

      money_market::enter_market<BTC>(&mut money_market_storage, ctx(test));

      let (coin_eth, coin_ipx) = money_market::borrow<ETH>(
        &mut money_market_storage,
        &interest_rate_model_storage,
        &mut ipx_storage,
        get_all_prices_potatoes(),
        &clock_object,
        borrow_value,
        ctx(test)
       );

      burn(coin_eth);
      burn(coin_ipx);

      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(money_market_storage); 
    };

    next_tx(test, alice);
    {
      let money_market_storage = test::take_shared<MoneyMarketStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);

      clock::increment_for_testing(&mut clock_object, 350000);

      let coin_ipx = money_market::repay<ETH>(
        &mut money_market_storage,
        &mut interest_rate_model_storage,
        &mut ipx_storage,
        &clock_object,
        mint<ETH>(30, ETH_DECIMALS, ctx(test)),
        (25 * ETH_DECIMALS_FACTOR as u64),
        ctx(test)
      );

      let loan_rewards_per_share = calculate_eth_market_rewards(350000, 50 * ETH_DECIMALS_FACTOR);
      let (_, loan, _, loan_rewards_paid) = money_market::get_account_info<ETH>(&money_market_storage, alice);

      assert_eq((burn(coin_ipx) as u256), loan_rewards_per_share * 50);
      assert_eq(loan, (25 * ETH_DECIMALS_FACTOR as u64));
      assert_eq(loan_rewards_paid, loan_rewards_per_share * 25);

      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(money_market_storage); 
    };

    next_tx(test, alice);
    {
      let money_market_storage = test::take_shared<MoneyMarketStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);

      let (_, _, _, _, _, _, _, _, _, _, prev_loan_rewards_per_share, _, _, _, _, _) = money_market::get_market_info<ETH>(&money_market_storage);

      let (_, prev_loan, _, prev_loan_rewards_paid) = money_market::get_account_info<ETH>(&money_market_storage, alice);

      clock::increment_for_testing(&mut clock_object, 350000);

      let coin_ipx = money_market::repay<ETH>(
        &mut money_market_storage,
        &mut interest_rate_model_storage,
        &mut ipx_storage,
        &clock_object,
        mint<ETH>(40, ETH_DECIMALS, ctx(test)),
        (25 * ETH_DECIMALS_FACTOR as u64),
        ctx(test)
      );

      let loan_rewards_per_share = calculate_eth_market_rewards(350000, 25 * ETH_DECIMALS_FACTOR) + prev_loan_rewards_per_share;
      let (_, loan, _, loan_rewards_paid) = money_market::get_account_info<ETH>(&money_market_storage, alice);

      assert_eq((burn(coin_ipx) as u256), (loan_rewards_per_share * (prev_loan as u256) / ETH_DECIMALS_FACTOR) - prev_loan_rewards_paid);
      assert_eq(loan, 0);
      assert_eq(loan_rewards_paid, 0);

      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(money_market_storage); 
    };

    clock::destroy_for_testing(clock_object);
  }

  #[test]
  fun test_repay() {
    let scenario = scenario();
    test_repay_(&mut scenario);
    test::end(scenario);    
  }

  #[test]
  #[expected_failure(abort_code = money_market::ipx_money_market::ERROR_SUID_OPERATION_NOT_ALLOWED)]
  fun test_fail_deposit_suid() {
    let scenario = scenario();

    let test = &mut scenario;

    init_test(test);

    let (alice, _) = people();
    let clock_object = clock::create_for_testing(ctx(test));

    next_tx(test, alice);
    {
      let money_market_storage = test::take_shared<MoneyMarketStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);

      burn(money_market::deposit<SUID>(
        &mut money_market_storage,
        &interest_rate_model_storage,
        &mut ipx_storage,
        &clock_object,
        mint<SUID>(10, SUID_DECIMALS, ctx(test)),
        ctx(test)
      ));

      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(money_market_storage);
   };

    clock::destroy_for_testing(clock_object);
    test::end(scenario);
  }

  #[test]
  #[expected_failure(abort_code = money_market::ipx_money_market::ERROR_MARKET_IS_PAUSED)]
  fun test_fail_deposit_paused() {
    let scenario = scenario();

    let test = &mut scenario;

    init_test(test);
    let clock_object = clock::create_for_testing(ctx(test));
    let (alice, _) = people();

    next_tx(test, alice);
    {
      let money_market_storage = test::take_shared<MoneyMarketStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);
      let money_market_admin_cap = test::take_from_address<MoneyMarketAdminCap>(test, alice);

      money_market::pause_market<BTC>(&money_market_admin_cap, &mut money_market_storage);

      burn(money_market::deposit<BTC>(
        &mut money_market_storage,
        &interest_rate_model_storage,
        &mut ipx_storage,
        &clock_object,
        mint<BTC>(10, SUID_DECIMALS, ctx(test)),
        ctx(test)
      ));

      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(money_market_storage);
      test::return_to_address(alice, money_market_admin_cap);
   };
    
    clock::destroy_for_testing(clock_object);
    test::end(scenario);
  }

  #[test]
  #[expected_failure(abort_code = money_market::ipx_money_market::ERROR_MAX_COLLATERAL_REACHED)]
  fun test_fail_deposit_borrow_cap_reached() {
    let scenario = scenario();

    let test = &mut scenario;

    init_test(test);

    let (alice, _) = people();
    let clock_object = clock::create_for_testing(ctx(test));

    next_tx(test, alice);
    {
      let money_market_storage = test::take_shared<MoneyMarketStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);

      burn(money_market::deposit<BTC>(
        &mut money_market_storage,
        &interest_rate_model_storage,
        &mut ipx_storage,
        &clock_object,
        mint<BTC>(BTC_BORROW_CAP * 2 + 1, 0, ctx(test)),
        ctx(test)
      ));

      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(money_market_storage);
   };

    clock::destroy_for_testing(clock_object);
    test::end(scenario);
  }

  #[test]
  #[expected_failure(abort_code = money_market::ipx_money_market::ERROR_SUID_OPERATION_NOT_ALLOWED)]
  fun test_fail_withdraw_suid() {
    let scenario = scenario();

    let test = &mut scenario;

    init_test(test);

    let (alice, _) = people();
    let clock_object = clock::create_for_testing(ctx(test));

    next_tx(test, alice);
    {
      let money_market_storage = test::take_shared<MoneyMarketStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);

      let (coin_btc, coin_ipx) = money_market::withdraw<SUID>(
        &mut money_market_storage, 
        &interest_rate_model_storage, 
        &mut ipx_storage, 
        get_all_prices_potatoes(), 
        &clock_object,
        0, 
        ctx(test)
      );

      burn(coin_btc);
      burn(coin_ipx);

      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(money_market_storage); 
   };
    
    clock::destroy_for_testing(clock_object);
    test::end(scenario);
  }

  #[test]
  #[expected_failure(abort_code = money_market::ipx_money_market::ERROR_NOT_ENOUGH_SHARES_IN_THE_ACCOUNT)]
  fun test_fail_withdraw_not_enough_shares() {
    let scenario = scenario();

    let test = &mut scenario;

    init_test(test);

    let (alice, _) = people();
    let clock_object = clock::create_for_testing(ctx(test));

    next_tx(test, alice);
    {
      let money_market_storage = test::take_shared<MoneyMarketStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);

      burn(money_market::deposit<BTC>(
        &mut money_market_storage,
        &interest_rate_model_storage,
        &mut ipx_storage,
        &clock_object,
        mint<BTC>(10, BTC_DECIMALS, ctx(test)),
        ctx(test)
      ));


      let (coin_btc, coin_ipx) = money_market::withdraw<BTC>(
        &mut money_market_storage, 
        &interest_rate_model_storage, 
        &mut ipx_storage, 
        get_all_prices_potatoes(),
        &clock_object,
        (11 * BTC_DECIMALS_FACTOR as u64), 
        ctx(test)
      );

      burn(coin_btc);
      burn(coin_ipx);

      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(money_market_storage); 
   };

    clock::destroy_for_testing(clock_object);
    test::end(scenario);
  }

  #[test]
  #[expected_failure(abort_code = money_market::ipx_money_market::ERROR_NOT_ENOUGH_CASH_TO_WITHDRAW)]
  fun test_fail_withdraw_no_cash() {
    let scenario = scenario();

    let test = &mut scenario;
    let clock_object = clock::create_for_testing(ctx(test));
    init_test(test);

    let (alice, bob) = people();

    next_tx(test, alice);
    {
      let money_market_storage = test::take_shared<MoneyMarketStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);

      burn(money_market::deposit<BTC>(
        &mut money_market_storage,
        &interest_rate_model_storage,
        &mut ipx_storage,
        &clock_object,
        mint<BTC>(10, BTC_DECIMALS, ctx(test)),
        ctx(test)
      ));

      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(money_market_storage); 
   };

    next_tx(test, bob);
    {
      let money_market_storage = test::take_shared<MoneyMarketStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);

      burn(money_market::deposit<ETH>(
        &mut money_market_storage,
        &interest_rate_model_storage,
        &mut ipx_storage,
        &clock_object,
        mint<ETH>(200, ETH_DECIMALS, ctx(test)),
        ctx(test)
      ));

      money_market::enter_market<ETH>(&mut money_market_storage, ctx(test));

      let (coin_eth, coin_ipx) = money_market::borrow<BTC>(
        &mut money_market_storage,
        &interest_rate_model_storage,
        &mut ipx_storage,
        get_all_prices_potatoes(),
        &clock_object,
        (5 * BTC_DECIMALS_FACTOR as u64), 
        ctx(test)
       );

       burn(coin_eth);
       burn(coin_ipx);

      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(money_market_storage); 
   };

    next_tx(test, alice);
    {
      let money_market_storage = test::take_shared<MoneyMarketStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);

      let (coin_btc, coin_ipx) = money_market::withdraw<BTC>(
        &mut money_market_storage, 
        &interest_rate_model_storage, 
        &mut ipx_storage, 
        get_all_prices_potatoes(),
        &clock_object,
        (6 * BTC_DECIMALS_FACTOR as u64), 
        ctx(test)
      );

      burn(coin_btc);
      burn(coin_ipx);

      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(money_market_storage); 
   };

    test::end(scenario);
    clock::destroy_for_testing(clock_object);
  }

  #[test]
  #[expected_failure(abort_code = money_market::ipx_money_market::ERROR_MARKET_IS_PAUSED)]
  fun test_fail_withdraw_paused() {
    let scenario = scenario();

    let test = &mut scenario;
    let clock_object = clock::create_for_testing(ctx(test));
    init_test(test);

    let (alice, _) = people();

    next_tx(test, alice);
    {
      let money_market_storage = test::take_shared<MoneyMarketStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);
      let money_market_admin_cap = test::take_from_address<MoneyMarketAdminCap>(test, alice);

      burn(money_market::deposit<BTC>(
        &mut money_market_storage,
        &interest_rate_model_storage,
        &mut ipx_storage,
        &clock_object,
        mint<BTC>(10, BTC_DECIMALS, ctx(test)),
        ctx(test)
      ));

      money_market::pause_market<BTC>(&money_market_admin_cap, &mut money_market_storage);

      let (coin_btc, coin_ipx) = money_market::withdraw<BTC>(
        &mut money_market_storage, 
        &interest_rate_model_storage, 
        &mut ipx_storage, 
        get_all_prices_potatoes(),
        &clock_object,
        1, 
        ctx(test)
      );

      burn(coin_btc);
      burn(coin_ipx);

      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(money_market_storage); 
      test::return_to_address(alice, money_market_admin_cap);
    };

    clock::destroy_for_testing(clock_object);
    test::end(scenario);
  }

  #[test]
  #[expected_failure(abort_code = money_market::ipx_money_market::ERROR_USER_IS_INSOLVENT)]
  fun test_fail_withdraw_insolvent() {
    let scenario = scenario();

    let test = &mut scenario;
    let clock_object = clock::create_for_testing(ctx(test));

    init_test(test);

    let (alice, bob) = people();

    next_tx(test, alice);
    {
      let money_market_storage = test::take_shared<MoneyMarketStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);

      burn(money_market::deposit<BTC>(
        &mut money_market_storage,
        &interest_rate_model_storage,
        &mut ipx_storage,
        &clock_object,
        mint<BTC>(10, BTC_DECIMALS, ctx(test)),
        ctx(test)
      ));

      money_market::enter_market<BTC>(&mut money_market_storage, ctx(test));

      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(money_market_storage); 
   };

    next_tx(test, bob);
    {
      let money_market_storage = test::take_shared<MoneyMarketStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);

      burn(money_market::deposit<ETH>(
        &mut money_market_storage,
        &interest_rate_model_storage,
        &mut ipx_storage,
        &clock_object,
        mint<ETH>(100, ETH_DECIMALS, ctx(test)),
        ctx(test)
      ));

      money_market::enter_market<BTC>(&mut money_market_storage, ctx(test));

      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(money_market_storage); 
   };

   next_tx(test, alice);
   {
      let money_market_storage = test::take_shared<MoneyMarketStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);

      let (coin_eth, coin_ipx) = money_market::borrow<ETH>(
        &mut money_market_storage,
        &interest_rate_model_storage,
        &mut ipx_storage,
        get_all_prices_potatoes(),
        &clock_object,
        (60 * ETH_DECIMALS_FACTOR as u64),
        ctx(test)
       );

       burn(coin_eth);
       burn(coin_ipx);

      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(money_market_storage); 
   };

    next_tx(test, alice);
    {
      let money_market_storage = test::take_shared<MoneyMarketStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);
      let money_market_admin_cap = test::take_from_address<MoneyMarketAdminCap>(test, alice);

      let (coin_btc, coin_ipx) = money_market::withdraw<BTC>(
        &mut money_market_storage, 
        &interest_rate_model_storage, 
        &mut ipx_storage, 
        get_all_prices_potatoes(), 
        &clock_object,
        (8 * BTC_DECIMALS_FACTOR as u64), 
        ctx(test)
      );

      burn(coin_btc);
      burn(coin_ipx);

      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(money_market_storage); 
      test::return_to_address(alice, money_market_admin_cap);
    };

    clock::destroy_for_testing(clock_object);
    test::end(scenario);
  }

  #[test]
  #[expected_failure(abort_code = money_market::ipx_money_market::ERROR_SUID_OPERATION_NOT_ALLOWED)]
  fun test_fail_borrow() {
    let scenario = scenario();

    let test = &mut scenario;

    init_test(test);
    let clock_object = clock::create_for_testing(ctx(test));

    let (alice, _) = people();

    next_tx(test, alice);
    {
      let money_market_storage = test::take_shared<MoneyMarketStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);

      let (coin_suid, coin_ipx) = money_market::borrow<SUID>(
        &mut money_market_storage,
        &interest_rate_model_storage,
        &mut ipx_storage,
        get_all_prices_potatoes(),
        &clock_object,
        0,
        ctx(test)
       );

      burn(coin_suid);
      burn(coin_ipx);

      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(money_market_storage); 
   };

    clock::destroy_for_testing(clock_object);
    test::end(scenario);
  }

  #[test]
  #[expected_failure(abort_code = money_market::ipx_money_market::ERROR_NOT_ENOUGH_CASH_TO_LEND)]
  fun test_fail_borrow_not_enough_cash() {
    let scenario = scenario();

    let test = &mut scenario;

    init_test(test);
    let clock_object = clock::create_for_testing(ctx(test));

    let (alice, bob) = people();

    next_tx(test, alice);
    {
      let money_market_storage = test::take_shared<MoneyMarketStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);

      burn(money_market::deposit<BTC>(
        &mut money_market_storage,
        &interest_rate_model_storage,
        &mut ipx_storage,
        &clock_object,
        mint<BTC>(10, BTC_DECIMALS, ctx(test)),
        ctx(test)
      ));

      money_market::enter_market<BTC>(&mut money_market_storage, ctx(test));

      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(money_market_storage);      
    };

    next_tx(test, bob);
    {
      let money_market_storage = test::take_shared<MoneyMarketStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);

      burn(money_market::deposit<ETH>(
        &mut money_market_storage,
        &interest_rate_model_storage,
        &mut ipx_storage,
        &clock_object,
        mint<ETH>(10, ETH_DECIMALS, ctx(test)),
        ctx(test)
      ));

      money_market::enter_market<BTC>(&mut money_market_storage, ctx(test));

      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(money_market_storage);    
    };

    next_tx(test, alice);
   {
      let money_market_storage = test::take_shared<MoneyMarketStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);

      money_market::enter_market<BTC>(&mut money_market_storage, ctx(test));

      let (coin_eth, coin_ipx) = money_market::borrow<ETH>(
        &mut money_market_storage,
        &interest_rate_model_storage,
        &mut ipx_storage,
        get_all_prices_potatoes(),
        &clock_object,
        (11 * ETH_DECIMALS_FACTOR as u64),
        ctx(test)
       );

      burn(coin_eth);
      burn(coin_ipx);

      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(money_market_storage); 
   };

    clock::destroy_for_testing(clock_object);
    test::end(scenario);
  }

  #[test]
  #[expected_failure(abort_code = money_market::ipx_money_market::ERROR_MARKET_IS_PAUSED)]
  fun test_fail_borrow_paused() {
    let scenario = scenario();

    let test = &mut scenario;

    init_test(test);
    let clock_object = clock::create_for_testing(ctx(test));
    let (alice, bob) = people();

    next_tx(test, alice);
    {
      let money_market_storage = test::take_shared<MoneyMarketStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);

      burn(money_market::deposit<BTC>(
        &mut money_market_storage,
        &interest_rate_model_storage,
        &mut ipx_storage,
        &clock_object,
        mint<BTC>(10, BTC_DECIMALS, ctx(test)),
        ctx(test)
      ));

      money_market::enter_market<BTC>(&mut money_market_storage, ctx(test));

      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(money_market_storage); 
    };

    next_tx(test, bob);
    {
      let money_market_storage = test::take_shared<MoneyMarketStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);

      burn(money_market::deposit<ETH>(
        &mut money_market_storage,
        &interest_rate_model_storage,
        &mut ipx_storage,
        &clock_object,
        mint<ETH>(10, ETH_DECIMALS, ctx(test)),
        ctx(test)
      ));

      money_market::enter_market<BTC>(&mut money_market_storage, ctx(test));

      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(money_market_storage);    
    };

    next_tx(test, alice);
   {
      let money_market_storage = test::take_shared<MoneyMarketStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);
      let money_market_admin_cap = test::take_from_address<MoneyMarketAdminCap>(test, alice);

      money_market::enter_market<BTC>(&mut money_market_storage, ctx(test));
      money_market::pause_market<ETH>(&money_market_admin_cap, &mut money_market_storage);

      let (coin_eth, coin_ipx) = money_market::borrow<ETH>(
        &mut money_market_storage,
        &interest_rate_model_storage,
        &mut ipx_storage,
        get_all_prices_potatoes(),
        &clock_object,
        (2 * ETH_DECIMALS_FACTOR as u64),
        ctx(test)
       );

      burn(coin_eth);
      burn(coin_ipx);

      test::return_to_address(alice, money_market_admin_cap);
      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(money_market_storage); 
   };

    clock::destroy_for_testing(clock_object);
    test::end(scenario);
  }

  #[test]
  #[expected_failure(abort_code = money_market::ipx_money_market::ERROR_BORROW_CAP_LIMIT_REACHED)]
  fun test_fail_borrow_cap_reached() {
    let scenario = scenario();

    let test = &mut scenario;

    init_test(test);

    let (alice, bob) = people();
    let clock_object = clock::create_for_testing(ctx(test));

    next_tx(test, alice);
    {
      let money_market_storage = test::take_shared<MoneyMarketStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);

      burn(money_market::deposit<BTC>(
        &mut money_market_storage,
        &interest_rate_model_storage,
        &mut ipx_storage,
        &clock_object,
        mint<BTC>(10, BTC_DECIMALS, ctx(test)),
        ctx(test)
      ));

      money_market::enter_market<BTC>(&mut money_market_storage, ctx(test));

      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(money_market_storage); 
    };

    next_tx(test, bob);
    {
      let money_market_storage = test::take_shared<MoneyMarketStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);

      burn(money_market::deposit<ETH>(
        &mut money_market_storage,
        &interest_rate_model_storage,
        &mut ipx_storage,
        &clock_object,
        mint<ETH>(10, ETH_DECIMALS, ctx(test)),
        ctx(test)
      ));

      money_market::enter_market<BTC>(&mut money_market_storage, ctx(test));

      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(money_market_storage); 
    };

    next_tx(test, alice);
   {
      let money_market_storage = test::take_shared<MoneyMarketStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);
      let money_market_admin_cap = test::take_from_address<MoneyMarketAdminCap>(test, alice);

      money_market::enter_market<BTC>(&mut money_market_storage, ctx(test));
      money_market::set_borrow_cap<ETH>(&money_market_admin_cap, &mut money_market_storage, (ETH_DECIMALS_FACTOR as u64));

      let (coin_eth, coin_ipx) = money_market::borrow<ETH>(
        &mut money_market_storage,
        &interest_rate_model_storage,
        &mut ipx_storage,
        get_all_prices_potatoes(),
        &clock_object,
        (2 * ETH_DECIMALS_FACTOR as u64),
        ctx(test)
       );

       burn(coin_eth);
       burn(coin_ipx);

      test::return_to_address(alice, money_market_admin_cap);
      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(money_market_storage); 
   };

    clock::destroy_for_testing(clock_object);
    test::end(scenario);
  }

  #[test]
  #[expected_failure(abort_code = money_market::ipx_money_market::ERROR_USER_IS_SOLVENT)]
  fun test_fail_borrow_insolvent() {
    let scenario = scenario();

    let test = &mut scenario;
    let clock_object = clock::create_for_testing(ctx(test));

    init_test(test);

    let (alice, bob) = people();

    next_tx(test, alice);
    {
      let money_market_storage = test::take_shared<MoneyMarketStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);

      burn(money_market::deposit<BTC>(
        &mut money_market_storage,
        &interest_rate_model_storage,
        &mut ipx_storage,
        &clock_object,
        mint<BTC>(10, BTC_DECIMALS, ctx(test)),
        ctx(test)
      ));

      money_market::enter_market<BTC>(&mut money_market_storage, ctx(test));

      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(money_market_storage); 
    };

    next_tx(test, bob);
    {
      let money_market_storage = test::take_shared<MoneyMarketStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);

      burn(money_market::deposit<ETH>(
        &mut money_market_storage,
        &interest_rate_model_storage,
        &mut ipx_storage,
        &clock_object,
        mint<ETH>(200, ETH_DECIMALS, ctx(test)),
        ctx(test)
      ));

      money_market::enter_market<BTC>(&mut money_market_storage, ctx(test));

      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(money_market_storage); 
    };

    next_tx(test, alice);
   {
      let money_market_storage = test::take_shared<MoneyMarketStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);
      let money_market_admin_cap = test::take_from_address<MoneyMarketAdminCap>(test, alice);

      money_market::enter_market<BTC>(&mut money_market_storage, ctx(test));

      let (coin_eth, coin_ipx) = money_market::borrow<ETH>(
        &mut money_market_storage,
        &interest_rate_model_storage,
        &mut ipx_storage,
        get_all_prices_potatoes(),
        &clock_object,
        (101 * ETH_DECIMALS_FACTOR as u64),
        ctx(test)
       );

      burn(coin_eth);
      burn(coin_ipx);

      test::return_to_address(alice, money_market_admin_cap);
      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(money_market_storage); 
   };

    clock::destroy_for_testing(clock_object);
    test::end(scenario);
  }

  #[test]
  #[expected_failure(abort_code = money_market::ipx_money_market::ERROR_SUID_OPERATION_NOT_ALLOWED)]
  fun test_fail_repay_suid() {
    let scenario = scenario();

    let test = &mut scenario;

    init_test(test);
    let clock_object = clock::create_for_testing(ctx(test));

    let (alice, _) = people();

    next_tx(test, alice);
    {
      let money_market_storage = test::take_shared<MoneyMarketStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);

      burn(money_market::repay<SUID>(
        &mut money_market_storage,
        &mut interest_rate_model_storage,
        &mut ipx_storage,
        &clock_object,
        mint<SUID>(30, ETH_DECIMALS, ctx(test)),
        0,
        ctx(test)
      ));

      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(money_market_storage);
   };

    clock::destroy_for_testing(clock_object);
    test::end(scenario);
  }

  #[test]
  #[expected_failure(abort_code = money_market::ipx_money_market::ERROR_MARKET_IS_PAUSED)]
  fun test_fail_repay_paused() {
    let scenario = scenario();

    let test = &mut scenario;

    init_test(test);
    let clock_object = clock::create_for_testing(ctx(test));

    let (alice, bob) = people();

    next_tx(test, alice);
    {
      let money_market_storage = test::take_shared<MoneyMarketStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);

      burn(money_market::deposit<BTC>(
        &mut money_market_storage,
        &interest_rate_model_storage,
        &mut ipx_storage,
        &clock_object,
        mint<BTC>(10, BTC_DECIMALS, ctx(test)),
        ctx(test)
       ));

      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(money_market_storage); 
    };

    next_tx(test, bob);
    {
      let money_market_storage = test::take_shared<MoneyMarketStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);

      burn(money_market::deposit<ETH>(
        &mut money_market_storage,
        &interest_rate_model_storage,
        &mut ipx_storage,
        &clock_object,
        mint<ETH>(300, ETH_DECIMALS, ctx(test)),
        ctx(test)
       ));

      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(money_market_storage); 
    };

    next_tx(test, alice);
    {
      let money_market_storage = test::take_shared<MoneyMarketStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);

      money_market::enter_market<BTC>(&mut money_market_storage, ctx(test));

      let (coin_eth, coin_ipx) = money_market::borrow<ETH>(
        &mut money_market_storage,
        &interest_rate_model_storage,
        &mut ipx_storage,
        get_all_prices_potatoes(),
        &clock_object,
        (10 * ETH_DECIMALS_FACTOR as u64),
        ctx(test)
       );

      burn(coin_eth);
      burn(coin_ipx);

      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(money_market_storage); 
    };
    next_tx(test, alice);
    {
      let money_market_storage = test::take_shared<MoneyMarketStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);
      let money_market_admin_cap = test::take_from_address<MoneyMarketAdminCap>(test, alice);

      money_market::pause_market<ETH>(&money_market_admin_cap, &mut money_market_storage);

      burn(money_market::repay<ETH>(
        &mut money_market_storage,
        &mut interest_rate_model_storage,
        &mut ipx_storage,
        &clock_object,
        mint<ETH>(10, ETH_DECIMALS, ctx(test)),
        0,
        ctx(test)
      ));

      test::return_to_address(alice, money_market_admin_cap);
      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(money_market_storage);
   };
    
    clock::destroy_for_testing(clock_object);
    test::end(scenario);
  }

  #[test]
  fun test_exit_market() {
    let scenario = scenario();

    let test = &mut scenario;

    init_test(test);
    let clock_object = clock::create_for_testing(ctx(test));
    let (alice, _) = people();

    next_tx(test, alice);
    {
      let money_market_storage = test::take_shared<MoneyMarketStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);

      burn(money_market::deposit<BTC>(
        &mut money_market_storage,
        &interest_rate_model_storage,
        &mut ipx_storage,
        &clock_object,
        mint<BTC>(5, BTC_DECIMALS, ctx(test)),
        ctx(test)
      ));

      burn(money_market::deposit<ADA>(
        &mut money_market_storage,
        &interest_rate_model_storage,
        &mut ipx_storage,
        &clock_object,
        mint<ADA>(10000, ADA_DECIMALS, ctx(test)),
        ctx(test)
      ));

      money_market::enter_market<BTC>(&mut money_market_storage, ctx(test));
      money_market::enter_market<ADA>(&mut money_market_storage, ctx(test));

      let user_markets_in = money_market::get_user_markets_in(&mut money_market_storage, alice);

      assert_eq(vector::contains(user_markets_in, &get_type_name_string<BTC>()), true);
      assert_eq(vector::contains(user_markets_in, &get_type_name_string<ADA>()), true);

      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(money_market_storage);
    };

    next_tx(test, alice);
    {
      let money_market_storage = test::take_shared<MoneyMarketStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);

      let (coin_btc, coin_ipx) = money_market::borrow<BTC>(
        &mut money_market_storage,
        &interest_rate_model_storage,
        &mut ipx_storage,
        get_all_prices_potatoes(),
        &clock_object,
        (BTC_DECIMALS_FACTOR as u64),
        ctx(test)
       );

      burn(coin_btc);
      burn(coin_ipx);

      money_market::exit_market<ADA>(
        &mut money_market_storage,
        &interest_rate_model_storage,
        get_all_prices_potatoes(),
        &clock_object,
        ctx(test)
      );

      let user_markets_in = money_market::get_user_markets_in(&mut money_market_storage, alice);

      assert_eq(vector::contains(user_markets_in, &get_type_name_string<BTC>()), true);
      assert_eq(vector::contains(user_markets_in, &get_type_name_string<ADA>()), false);

      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(money_market_storage); 
    };

    clock::destroy_for_testing(clock_object);
    test::end(scenario);
  }

  #[test]
  #[expected_failure(abort_code = money_market::ipx_money_market::ERROR_MARKET_EXIT_LOAN_OPEN)]
  fun test_fail_exit_market_open_loan() {
    let scenario = scenario();

    let test = &mut scenario;
    let clock_object = clock::create_for_testing(ctx(test));

    init_test(test);

    let (alice, _) = people();

    next_tx(test, alice);
    {
      let money_market_storage = test::take_shared<MoneyMarketStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);

      burn(money_market::deposit<BTC>(
        &mut money_market_storage,
        &interest_rate_model_storage,
        &mut ipx_storage,
        &clock_object,
        mint<BTC>(5, BTC_DECIMALS, ctx(test)),
        ctx(test)
      ));

      money_market::enter_market<BTC>(&mut money_market_storage, ctx(test));

      let user_markets_in = money_market::get_user_markets_in(&money_market_storage, alice);

      assert_eq(vector::contains(user_markets_in, &get_type_name_string<BTC>()), true);

      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(money_market_storage);
    };

    next_tx(test, alice);
    {
      let money_market_storage = test::take_shared<MoneyMarketStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);

      let (coin_btc, coin_ipx) = money_market::borrow<BTC>(
        &mut money_market_storage,
        &interest_rate_model_storage,
        &mut ipx_storage,
        get_all_prices_potatoes(),
        &clock_object,
        (BTC_DECIMALS_FACTOR as u64),
        ctx(test)
       );

      burn(coin_btc);
      burn(coin_ipx);

      money_market::exit_market<BTC>(
        &mut money_market_storage,
        &interest_rate_model_storage,
        get_all_prices_potatoes(),
        &clock_object,
        ctx(test)
      );

      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(money_market_storage); 
    };

    clock::destroy_for_testing(clock_object);
    test::end(scenario);
  }

  #[test]
  #[expected_failure(abort_code = money_market::ipx_money_market::ERROR_USER_IS_INSOLVENT)]
  fun test_fail_exit_market_insolvent() {
    let scenario = scenario();

    let test = &mut scenario;
    let clock_object = clock::create_for_testing(ctx(test));

    init_test(test);

    let (alice, _) = people();

    next_tx(test, alice);
    {
      let money_market_storage = test::take_shared<MoneyMarketStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);

      burn(money_market::deposit<BTC>(
        &mut money_market_storage,
        &interest_rate_model_storage,
        &mut ipx_storage,
        &clock_object,
        mint<BTC>(10, BTC_DECIMALS, ctx(test)),
        ctx(test)
      ));

      burn(money_market::deposit<ADA>(
        &mut money_market_storage,
        &interest_rate_model_storage,
        &mut ipx_storage,
        &clock_object,
        mint<ADA>(500000, ADA_DECIMALS, ctx(test)),
        ctx(test)
      ));

      money_market::enter_market<BTC>(&mut money_market_storage, ctx(test));
      money_market::enter_market<ADA>(&mut money_market_storage, ctx(test));

      let user_markets_in = money_market::get_user_markets_in(&money_market_storage, alice);

      assert_eq(vector::contains(user_markets_in, &get_type_name_string<BTC>()), true);
      assert_eq(vector::contains(user_markets_in, &get_type_name_string<ADA>()), true);

      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(money_market_storage);
    };

    next_tx(test, alice);
    {
      let money_market_storage = test::take_shared<MoneyMarketStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);

      let (coin_btc, coin_ipx) = money_market::borrow<BTC>(
        &mut money_market_storage,
        &interest_rate_model_storage,
        &mut ipx_storage,
        get_all_prices_potatoes(),
        &clock_object,
        (8 * BTC_DECIMALS_FACTOR as u64),
        ctx(test)
       );

      burn(coin_btc);
      burn(coin_ipx);

      money_market::exit_market<ADA>(
        &mut money_market_storage,
        &interest_rate_model_storage,
        get_all_prices_potatoes(),
        &clock_object,
        ctx(test)
      );

      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(money_market_storage); 
    };

    clock::destroy_for_testing(clock_object);
    test::end(scenario);
  }


  #[test]
  #[expected_failure(abort_code = money_market::ipx_money_market::ERROR_CAN_NOT_BE_COLLATERAL)]
  fun test_fail_enter_market() {
    let scenario = scenario();

    let test = &mut scenario;

    init_test(test);
    let (alice, _) = people();

    next_tx(test, alice);
    {
      let money_market_storage = test::take_shared<MoneyMarketStorage>(test);
      let money_market_admin_cap = test::take_from_address<MoneyMarketAdminCap>(test, alice);

      money_market::update_can_be_collateral<BTC>(&money_market_admin_cap, &mut money_market_storage, false);

      money_market::enter_market<BTC>(&mut money_market_storage, ctx(test));

      test::return_to_address(alice, money_market_admin_cap);    
      test::return_shared(money_market_storage);
    };

    test::end(scenario);
  }

  #[test]
  fun test_get_account_balances() {
    let scenario = scenario();

    let test = &mut scenario;

    init_test(test);

    let (alice, bob) = people();
    let clock_object = clock::create_for_testing(ctx(test));

    next_tx(test, alice);
    {
      let money_market_storage = test::take_shared<MoneyMarketStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);

      burn(money_market::deposit<BTC>(
        &mut money_market_storage,
        &interest_rate_model_storage,
        &mut ipx_storage,
        &clock_object,
        mint<BTC>(10, BTC_DECIMALS, ctx(test)),
        ctx(test)
      ));

      money_market::enter_market<BTC>(&mut money_market_storage, ctx(test));

      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(money_market_storage);      
    };

    next_tx(test, bob);
    {
      let money_market_storage = test::take_shared<MoneyMarketStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);

      burn(money_market::deposit<ETH>(
        &mut money_market_storage,
        &interest_rate_model_storage,
        &mut ipx_storage,
        &clock_object,
        mint<ETH>(100, ETH_DECIMALS, ctx(test)),
        ctx(test)
      ));

      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(money_market_storage); 
    };

    next_tx(test, alice);
    {
      let money_market_storage = test::take_shared<MoneyMarketStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);

      let (coin_eth, coin_ipx) = money_market::borrow<ETH>(
        &mut money_market_storage,
        &interest_rate_model_storage,
        &mut ipx_storage,
        get_all_prices_potatoes(),
        &clock_object,
        (10 * ETH_DECIMALS_FACTOR as u64),
        ctx(test)
       );

      burn(coin_eth);
      burn(coin_ipx); 

      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(money_market_storage); 
    };

    next_tx(test, alice);
    {
      let money_market_storage = test::take_shared<MoneyMarketStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let suid_storage = test::take_shared<SuiDollarStorage>(test);

      let borrow_rate_per_ms = money_market::get_borrow_rate_per_ms<ETH>(
        &money_market_storage,
        &interest_rate_model_storage
      );

      clock::increment_for_testing(&mut clock_object, (MS_PER_YEAR as u64));

      let borrow_amount = (10 * ETH_DECIMALS_FACTOR as u64);

      let accumulated_borrow_interest_rate = borrow_rate_per_ms * (MS_PER_YEAR as u64);

      let interest_rate_amount = d_fmul(borrow_amount, accumulated_borrow_interest_rate);

      let reserve_amount = d_fmul_u256(interest_rate_amount, (INITIAL_RESERVE_FACTOR_MANTISSA as u256));

      let (alice_collateral, alice_borrows) = money_market::get_account_balances<ETH>(
        &mut money_market_storage,
        &interest_rate_model_storage,
        &clock_object,
        alice
      );

      let (bob_collateral, bob_borrows) = money_market::get_account_balances<ETH>(
        &mut money_market_storage,
        &interest_rate_model_storage,
        &clock_object,
        bob
      );

      assert_eq(alice_collateral, 0);
      assert_eq(alice_borrows, borrow_amount + (interest_rate_amount as u64));
      assert_eq(bob_collateral, (100 * ETH_DECIMALS_FACTOR as u64) + (interest_rate_amount as u64) - (reserve_amount as u64));
      assert_eq(bob_borrows, 0);
      // sanity test computer off chain
      assert_eq(interest_rate_amount, 21999955);

      test::return_shared(suid_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(money_market_storage); 
    };

    clock::destroy_for_testing(clock_object);
    test::end(scenario);
  }

  #[test]
  #[expected_failure(abort_code = money_market::ipx_money_market::ERROR_SUID_OPERATION_NOT_ALLOWED)]
  fun test_fail_set_interest_rate_data_suid() {
    let scenario = scenario();

    let test = &mut scenario;

    init_test(test);
    let clock_object = clock::create_for_testing(ctx(test));

    let (alice, _) = people();
    next_tx(test, alice);
    {
      let money_market_storage = test::take_shared<MoneyMarketStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let money_market_admin_cap = test::take_from_address<MoneyMarketAdminCap>(test, alice);

      money_market::set_interest_rate_data<SUID>(
        &money_market_admin_cap,
        &mut money_market_storage,
        &mut interest_rate_model_storage,
        &clock_object,
        1000000000,
        2000000000,
        3000000000,
        50000000000,
        ctx(test)
      );

      test::return_to_address(alice, money_market_admin_cap);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(money_market_storage);
    };

    clock::destroy_for_testing(clock_object);
    test::end(scenario);
  }

  #[test]
  fun test_set_interest_rate_data() {
    let scenario = scenario();

    let test = &mut scenario;

    init_test(test);
    let clock_object = clock::create_for_testing(ctx(test));

    let (alice, _) = people();
    next_tx(test, alice);
    {
      let money_market_storage = test::take_shared<MoneyMarketStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let money_market_admin_cap = test::take_from_address<MoneyMarketAdminCap>(test, alice);

      money_market::set_interest_rate_data<BTC>(
        &money_market_admin_cap,
        &mut money_market_storage,
        &mut interest_rate_model_storage,
        &clock_object,
        10000000000000000,
        20000000000000000,
        30000000000000000,
        500000000000000000,
        ctx(test)
      );

      let (base, multiplier, jump, kink) = model::get_interest_rate_data<BTC>(&interest_rate_model_storage);

      assert_eq(base, 10000000000000000 / MS_PER_YEAR);
      assert_eq(multiplier, 20000000000000000 / MS_PER_YEAR);
      assert_eq(jump, 30000000000000000 / MS_PER_YEAR);
      assert_eq(kink, 500000000000000000);

      test::return_to_address(alice, money_market_admin_cap);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(money_market_storage);
    };

    clock::destroy_for_testing(clock_object);
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
      let money_market_storage = test::take_shared<MoneyMarketStorage>(test);
      let money_market_admin_cap = test::take_from_address<MoneyMarketAdminCap>(test, alice);

      money_market::update_liquidation<BTC>(
        &money_market_admin_cap,
        &mut money_market_storage,
        500, 
        300
      );

      let (penalty_fee, protocol_fee) = money_market::get_liquidation_info<BTC>(&money_market_storage);

      assert_eq(penalty_fee, 500);
      assert_eq(protocol_fee, 300);

      test::return_to_address(alice, money_market_admin_cap);
      test::return_shared(money_market_storage);
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
      let money_market_storage = test::take_shared<MoneyMarketStorage>(test);
      let money_market_admin_cap = test::take_from_address<MoneyMarketAdminCap>(test, alice);

      money_market::pause_market<BTC>(
        &money_market_admin_cap,
        &mut money_market_storage
      );

      let paused = money_market::is_market_paused<BTC>(&money_market_storage);

      assert_eq(paused, true);

      money_market::unpause_market<BTC>(
        &money_market_admin_cap,
        &mut money_market_storage
      );

      let paused = money_market::is_market_paused<BTC>(&money_market_storage);

      assert_eq(paused, false);

      test::return_to_address(alice, money_market_admin_cap);
      test::return_shared(money_market_storage);    
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
      let money_market_storage = test::take_shared<MoneyMarketStorage>(test);
      let money_market_admin_cap = test::take_from_address<MoneyMarketAdminCap>(test, alice);

      money_market::set_borrow_cap<BTC>(
        &money_market_admin_cap,
        &mut money_market_storage,
        2
      );

      let (_, _, borrow_cap, _, _, _, _, _, _, _, _, _, _, _, _, _) = money_market::get_market_info<BTC>(&money_market_storage);

      assert_eq(borrow_cap, 2);

      test::return_to_address(alice, money_market_admin_cap);
      test::return_shared(money_market_storage);    
    };
    test::end(scenario);
  }

  #[test]
  #[expected_failure(abort_code = money_market::ipx_money_market::ERROR_SUID_OPERATION_NOT_ALLOWED)]
  fun test_fail_update_reserve_factor_suid() {
    let scenario = scenario();

    let test = &mut scenario;

    init_test(test);
    let clock_object = clock::create_for_testing(ctx(test));
    let (alice, _) = people();

    next_tx(test, alice);
    {
      let money_market_storage = test::take_shared<MoneyMarketStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let money_market_admin_cap = test::take_from_address<MoneyMarketAdminCap>(test, alice);

      money_market::update_reserve_factor<SUID>(
        &money_market_admin_cap,
        &mut money_market_storage,
        &mut interest_rate_model_storage,
        &clock_object,
        10000,
      );

      test::return_to_address(alice, money_market_admin_cap);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(money_market_storage);
    };

    clock::destroy_for_testing(clock_object);
    test::end(scenario);
  }

  #[test]
  fun test_update_reserve_factor() {
    let scenario = scenario();

    let test = &mut scenario;

    init_test(test);
    let clock_object = clock::create_for_testing(ctx(test));
    let (alice, _) = people();

    next_tx(test, alice);
    {
      let money_market_storage = test::take_shared<MoneyMarketStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let money_market_admin_cap = test::take_from_address<MoneyMarketAdminCap>(test, alice);

      clock::increment_for_testing(&mut clock_object, 12000);

      money_market::update_reserve_factor<BTC>(
        &money_market_admin_cap,
        &mut money_market_storage,
        &mut interest_rate_model_storage,
        &clock_object,
        10000
      );

      let (_, accrued_timestamp, _, _, _, _, _, reserve_factor, _, _, _, _, _, _, _, _) = money_market::get_market_info<BTC>(&money_market_storage);

      assert_eq(accrued_timestamp, 12000);
      assert_eq(reserve_factor, 10000);

      test::return_to_address(alice, money_market_admin_cap);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(money_market_storage);
    };

    clock::destroy_for_testing(clock_object);
    test::end(scenario);
  }

  #[test]
  fun test_withdraw_reserves() {
    let scenario = scenario();

    let test = &mut scenario;

    init_test(test);
    let clock_object = clock::create_for_testing(ctx(test));

    let (alice, bob) = people();
    next_tx(test, alice);    
    {
      let money_market_storage = test::take_shared<MoneyMarketStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);

      burn(money_market::deposit<BTC>(
        &mut money_market_storage,
        &interest_rate_model_storage,
        &mut ipx_storage,
        &clock_object,
        mint<BTC>(10, BTC_DECIMALS, ctx(test)),
        ctx(test)
      ));

      money_market::enter_market<BTC>(&mut money_market_storage, ctx(test));

      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(money_market_storage);
    };

    next_tx(test, bob);
    {
      let money_market_storage = test::take_shared<MoneyMarketStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);

      burn(money_market::deposit<ETH>(
        &mut money_market_storage,
        &interest_rate_model_storage,
        &mut ipx_storage,
        &clock_object,
        mint<ETH>(100, ETH_DECIMALS, ctx(test)),
        ctx(test)
      ));

      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(money_market_storage);
    };

    next_tx(test, alice);
    {
      let money_market_storage = test::take_shared<MoneyMarketStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);

      let borrow_value = (10 * ETH_DECIMALS_FACTOR as u64);

      let (coin_eth, coin_ipx) = money_market::borrow<ETH>(
        &mut money_market_storage,
        &interest_rate_model_storage,
        &mut ipx_storage,
        get_all_prices_potatoes(),
        &clock_object,
        borrow_value,
        ctx(test)
       );

      burn(coin_eth);
      burn(coin_ipx); 

      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(money_market_storage);    
    };

    next_tx(test, alice);
    {
      let money_market_storage = test::take_shared<MoneyMarketStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);
      let suid_storage = test::take_shared<SuiDollarStorage>(test);
      let money_market_admin_cap = test::take_from_address<MoneyMarketAdminCap>(test, alice);

      clock::increment_for_testing(&mut clock_object, 120000000);

      let borrow_rate_per_ms = money_market::get_borrow_rate_per_ms<ETH>(
        &money_market_storage,
        &interest_rate_model_storage
      );

      let borrow_amount = (10 * ETH_DECIMALS_FACTOR as u64);

      let accumulated_borrow_interest_rate = borrow_rate_per_ms * 120000000;

      let interest_rate_amount = d_fmul(borrow_amount, accumulated_borrow_interest_rate);

      let reserve_amount = d_fmul_u256(interest_rate_amount, (INITIAL_RESERVE_FACTOR_MANTISSA as u256));

      money_market::withdraw_reserves<ETH>(
        &money_market_admin_cap,
        &mut money_market_storage,
        &interest_rate_model_storage,
        &mut suid_storage,
        &clock_object,
        (reserve_amount as u64),
        ctx(test)
      );

      let (total_reserves, accrued_timestamp, _, _, _, _, _, _, _, _, _, _, _, _, _, _) = money_market::get_market_info<ETH>(&money_market_storage);

      assert_eq(accrued_timestamp, 120000000);
      assert_eq(total_reserves, 0);
      
      test::return_to_address(alice, money_market_admin_cap);
      test::return_shared(suid_storage);
      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(money_market_storage); 
    };

    clock::destroy_for_testing(clock_object);
    test::end(scenario);
  }

  #[test]
  #[expected_failure(abort_code = money_market::ipx_money_market::ERROR_NOT_ENOUGH_CASH_TO_WITHDRAW)]
  fun test_fail_withdraw_reserves_no_cash() {
    let scenario = scenario();

    let test = &mut scenario;

    init_test(test);
    let clock_object = clock::create_for_testing(ctx(test));

    let (alice, bob) = people();
    next_tx(test, alice);    
    {
      let money_market_storage = test::take_shared<MoneyMarketStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);

      burn(money_market::deposit<BTC>(
        &mut money_market_storage,
        &interest_rate_model_storage,
        &mut ipx_storage,
        &clock_object,
        mint<BTC>(10, BTC_DECIMALS, ctx(test)),
        ctx(test)
      ));

      money_market::enter_market<BTC>(&mut money_market_storage, ctx(test));

      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(money_market_storage);
    };

    next_tx(test, bob);
    {
      let money_market_storage = test::take_shared<MoneyMarketStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);

      burn(money_market::deposit<ETH>(
        &mut money_market_storage,
        &interest_rate_model_storage,
        &mut ipx_storage,
        &clock_object,
        mint<ETH>(10, ETH_DECIMALS, ctx(test)),
        ctx(test)
      ));

      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(money_market_storage);
    };

    next_tx(test, alice);
    {
      let money_market_storage = test::take_shared<MoneyMarketStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);

      let borrow_value = (10 * ETH_DECIMALS_FACTOR as u64);

      let (coin_eth, coin_ipx) = money_market::borrow<ETH>(
        &mut money_market_storage,
        &interest_rate_model_storage,
        &mut ipx_storage,
        get_all_prices_potatoes(),
        &clock_object,
        borrow_value,
        ctx(test)
       );

      burn(coin_eth);
      burn(coin_ipx); 

      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(money_market_storage); 
    };

    next_tx(test, alice);
    {
      let money_market_storage = test::take_shared<MoneyMarketStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);
      let suid_storage = test::take_shared<SuiDollarStorage>(test);
      let money_market_admin_cap = test::take_from_address<MoneyMarketAdminCap>(test, alice);

      let borrow_rate_per_ms = money_market::get_borrow_rate_per_ms<ETH>(
        &money_market_storage,
        &interest_rate_model_storage
      );


      let borrow_amount = (10 * ETH_DECIMALS_FACTOR as u64);

      let accumulated_borrow_interest_rate = borrow_rate_per_ms * 120000000;

      let interest_rate_amount = d_fmul(borrow_amount, accumulated_borrow_interest_rate);

      let reserve_amount = d_fmul_u256(interest_rate_amount, (INITIAL_RESERVE_FACTOR_MANTISSA as u256));

      money_market::withdraw_reserves<ETH>(
        &money_market_admin_cap,
        &mut money_market_storage,
        &interest_rate_model_storage,
        &mut suid_storage,
        &clock_object,
        (reserve_amount as u64),
        ctx(test)
      );
    
      test::return_to_address(alice, money_market_admin_cap);
      test::return_shared(suid_storage);
      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(money_market_storage); 
    };

    clock::destroy_for_testing(clock_object);
    test::end(scenario);
  }

  #[test]
  #[expected_failure(abort_code = money_market::ipx_money_market::ERROR_NOT_ENOUGH_RESERVES)]
  fun test_fail_withdraw_reserves_not_enough_reserves() {
    let scenario = scenario();

    let test = &mut scenario;
    let clock_object = clock::create_for_testing(ctx(test));

    init_test(test);

    let (alice, bob) = people();
    next_tx(test, alice);    
    {
      let money_market_storage = test::take_shared<MoneyMarketStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);

      burn(money_market::deposit<BTC>(
        &mut money_market_storage,
        &interest_rate_model_storage,
        &mut ipx_storage,
        &clock_object,
        mint<BTC>(10, BTC_DECIMALS, ctx(test)),
        ctx(test)
      ));

      money_market::enter_market<BTC>(&mut money_market_storage, ctx(test));

      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(money_market_storage);
    };

    next_tx(test, bob);
    {
      let money_market_storage = test::take_shared<MoneyMarketStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);

      burn(money_market::deposit<ETH>(
        &mut money_market_storage,
        &interest_rate_model_storage,
        &mut ipx_storage,
        &clock_object,
        mint<ETH>(100, ETH_DECIMALS, ctx(test)),
        ctx(test)
      ));

      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(money_market_storage);
    };

    next_tx(test, alice);
    {
      let money_market_storage = test::take_shared<MoneyMarketStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);

      let borrow_value = (10 * ETH_DECIMALS_FACTOR as u64);

      let (coin_eth, coin_ipx) = money_market::borrow<ETH>(
        &mut money_market_storage,
        &interest_rate_model_storage,
        &mut ipx_storage,
        get_all_prices_potatoes(),
        &clock_object,
        borrow_value,
        ctx(test)
       );

      burn(coin_eth);
      burn(coin_ipx); 

      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(money_market_storage);      
    };

    next_tx(test, alice);
    {
      let money_market_storage = test::take_shared<MoneyMarketStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);
      let suid_storage = test::take_shared<SuiDollarStorage>(test);
      let money_market_admin_cap = test::take_from_address<MoneyMarketAdminCap>(test, alice);

      let borrow_rate_per_ms = money_market::get_borrow_rate_per_ms<ETH>(
        &money_market_storage,
        &interest_rate_model_storage
      );

      let timestame_increase = 462819017;

      clock::increment_for_testing(&mut clock_object, timestame_increase);

      let borrow_amount = (10 * ETH_DECIMALS_FACTOR as u64);

      let accumulated_borrow_interest_rate = borrow_rate_per_ms * timestame_increase;

      let interest_rate_amount = d_fmul(borrow_amount, accumulated_borrow_interest_rate);

      let reserve_amount = d_fmul_u256(interest_rate_amount, (INITIAL_RESERVE_FACTOR_MANTISSA as u256));

      money_market::withdraw_reserves<ETH>(
        &money_market_admin_cap,
        &mut money_market_storage,
        &interest_rate_model_storage,
        &mut suid_storage,
        &clock_object,
        (reserve_amount + 1 as u64),
        ctx(test)
      );
    
      test::return_to_address(alice, money_market_admin_cap);
      test::return_shared(suid_storage);
      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(money_market_storage); 
    };

    clock::destroy_for_testing(clock_object);
    test::end(scenario);
  }

  #[test]
  fun test_update_ltv() {
    let scenario = scenario();

    let test = &mut scenario;

    init_test(test);
    let clock_object = clock::create_for_testing(ctx(test));

    let (alice, _) = people();
    next_tx(test, alice);  
    {
      let money_market_storage = test::take_shared<MoneyMarketStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);
      let money_market_admin_cap = test::take_from_address<MoneyMarketAdminCap>(test, alice);

      money_market::update_ltv<BTC>(
        &money_market_admin_cap,
        &mut money_market_storage,
        &interest_rate_model_storage,
        &clock_object,
        100
      );

      let (_, _, _, _, _, _, ltv, _, _, _, _, _, _, _, _, _) = money_market::get_market_info<BTC>(&money_market_storage);

      assert_eq(ltv, 100);
    
      test::return_to_address(alice, money_market_admin_cap);
      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(money_market_storage); 
    }; 

    clock::destroy_for_testing(clock_object);
    test::end(scenario);
  }

  #[test]
  fun test_update_suid_interest_rate_per_epoch() {
    let scenario = scenario();

    let test = &mut scenario;

    init_test(test);
    let clock_object = clock::create_for_testing(ctx(test));

    let (alice, _) = people();
    next_tx(test, alice); 
    {
      let money_market_storage = test::take_shared<MoneyMarketStorage>(test);
      let money_market_admin_cap = test::take_from_address<MoneyMarketAdminCap>(test, alice);

      let timestamp_delta = 292727282;

      clock::increment_for_testing(&mut clock_object, timestamp_delta);

      money_market::update_suid_interest_rate_per_ms(
        &money_market_admin_cap,
        &mut money_market_storage,
        &clock_object,
        30000000
      );

      let suid_per_ms = money_market::get_interest_rate_per_ms(&money_market_storage);
      let (_, accrued_timestamp, _, _, _, _, _, _, _, _, _, _, _, _, _, _) = money_market::get_market_info<SUID>(&money_market_storage);

      assert_eq(accrued_timestamp, timestamp_delta);
      assert_eq((suid_per_ms as u256), 30000000 / MS_PER_YEAR);

      test::return_to_address(alice, money_market_admin_cap);
      test::return_shared(money_market_storage);       
    };

    clock::destroy_for_testing(clock_object);
    test::end(scenario);
  }

  #[test]
  fun test_update_allocation_points() {
    let scenario = scenario();

    let test = &mut scenario;

    init_test(test);
    let clock_object = clock::create_for_testing(ctx(test));

    let (alice, _) = people();
    next_tx(test, alice); 
    {
      let money_market_storage = test::take_shared<MoneyMarketStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let money_market_admin_cap = test::take_from_address<MoneyMarketAdminCap>(test, alice);

      clock::increment_for_testing(&mut clock_object, 4);

      money_market::update_allocation_points<BTC>(
        &money_market_admin_cap,
        &mut money_market_storage,
        &interest_rate_model_storage,
        &clock_object,
        450
      );

      let (_, accrued_timestamp, _, _, _, _, _, _, allocation_points, _, _, _, _, _, _, _) = money_market::get_market_info<BTC>(&money_market_storage);
      let total_allocation_points = money_market::get_total_allocation_points(&money_market_storage);

      assert_eq(accrued_timestamp, 4);
      assert_eq(allocation_points, 450);
      assert_eq(total_allocation_points, 2550);

      test::return_to_address(alice, money_market_admin_cap);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(money_market_storage);    
    };

    clock::destroy_for_testing(clock_object);
    test::end(scenario);
  }

  #[test]
  fun test_update_ipx_per_epoch() {
    let scenario = scenario();

    let test = &mut scenario;

    init_test(test);
    let clock_object = clock::create_for_testing(ctx(test));

    let (alice, _) = people();
    next_tx(test, alice);
    {
      let money_market_storage = test::take_shared<MoneyMarketStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let money_market_admin_cap = test::take_from_address<MoneyMarketAdminCap>(test, alice);

      let timestame_increase = 2827261928;

      clock::increment_for_testing(&mut clock_object, timestame_increase);

      money_market::update_ipx_per_ms(
        &money_market_admin_cap,
        &mut money_market_storage,
        &interest_rate_model_storage,
        &clock_object,
        450
      );

      let (_, accrued_timestamp, _, _, _, _, _, _, _, _, _, _, _, _, _, _) = money_market::get_market_info<BTC>(&money_market_storage);
      assert_eq(accrued_timestamp, timestame_increase);

      let (_, accrued_timestamp, _, _, _, _, _, _, _, _, _, _, _, _, _, _) = money_market::get_market_info<ETH>(&money_market_storage);
      assert_eq(accrued_timestamp, timestame_increase);
      
      let (_, accrued_timestamp, _, _, _, _, _, _, _, _, _, _, _, _, _, _) = money_market::get_market_info<ADA>(&money_market_storage);
      assert_eq(accrued_timestamp, timestame_increase);

      let (_, accrued_timestamp, _, _, _, _, _, _, _, _, _, _, _, _, _, _) = money_market::get_market_info<SUID>(&money_market_storage);
      assert_eq(accrued_timestamp, timestame_increase);
      
      let ipx_per_ms = money_market::get_ipx_per_ms(&money_market_storage);
      assert_eq(ipx_per_ms, 450);

      let num_of_markets = money_market::get_total_num_of_markets(&money_market_storage);
      assert_eq(num_of_markets, 4);
      
      test::return_to_address(alice, money_market_admin_cap);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(money_market_storage);   
    }; 

    clock::destroy_for_testing(clock_object);
    test::end(scenario);
  }

  #[test]
  fun test_transfer_admin_cap() {
    let scenario = scenario();

    let test = &mut scenario;

    init_test(test);

    let (alice, bob) = people();
    next_tx(test, alice);
    {
      let money_market_admin_cap = test::take_from_address<MoneyMarketAdminCap>(test, alice);

      money_market::transfer_admin_cap(money_market_admin_cap, bob);
    };

    next_tx(test, bob);
    {
      let money_market_admin_cap = test::take_from_address<MoneyMarketAdminCap>(test, bob);
      test::return_to_address(bob, money_market_admin_cap);
    };
    test::end(scenario);
  }

  #[test]
  fun test_update_can_be_collateral() {
    let scenario = scenario();

    let test = &mut scenario;

    init_test(test);

    let (alice, _) = people();
    next_tx(test, alice);
    {
      let money_market_admin_cap = test::take_from_address<MoneyMarketAdminCap>(test, alice);
      let money_market_storage = test::take_shared<MoneyMarketStorage>(test);

      let (_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, can_be_collateral) = money_market::get_market_info<BTC>(&money_market_storage);

      assert_eq(can_be_collateral, true);

      money_market::update_can_be_collateral<BTC>(&money_market_admin_cap, &mut money_market_storage, false);

      let (_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, can_be_collateral) = money_market::get_market_info<BTC>(&money_market_storage);

      assert_eq(can_be_collateral, false);

      test::return_shared(money_market_storage); 
      test::return_to_address(alice, money_market_admin_cap);
    };

    test::end(scenario);
  }

  #[test]
  #[expected_failure(abort_code = money_market::ipx_money_market::ERROR_NO_ADDRESS_ZERO)]
  fun test_fail_transfer_admin_cap() {
    let scenario = scenario();

    let test = &mut scenario;

    init_test(test);

    let (alice, _) = people();
    next_tx(test, alice);
    {
      let money_market_admin_cap = test::take_from_address<MoneyMarketAdminCap>(test, alice);

      money_market::transfer_admin_cap(money_market_admin_cap, @0x0);
    };
    test::end(scenario);
  }

   #[test] 
   fun test_borrow_suid() {
    let scenario = scenario();

    let test = &mut scenario;
    init_test(test);

    let (alice, _) = people();
    let clock_object = clock::create_for_testing(ctx(test));
    
    next_tx(test, alice);
    {
      let money_market_storage = test::take_shared<MoneyMarketStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);

      burn(money_market::deposit<BTC>(
        &mut money_market_storage,
        &interest_rate_model_storage,
        &mut ipx_storage,
        &clock_object,
        mint<BTC>(5, BTC_DECIMALS, ctx(test)),
        ctx(test)
       ));

      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(money_market_storage); 
    };

    next_tx(test, alice);
    {
      let money_market_storage = test::take_shared<MoneyMarketStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);
      let suid_storage = test::take_shared<SuiDollarStorage>(test);

      // 60k
      let borrow_value = ( 60000 * SUID_DECIMALS_FACTOR as u64);

      money_market::enter_market<BTC>(&mut money_market_storage, ctx(test));

      let (coin_suid, coin_ipx) = money_market::borrow_suid(
        &mut money_market_storage,
        &interest_rate_model_storage,
        &mut ipx_storage,
        &mut suid_storage,
        get_all_prices_potatoes(),
        &clock_object,
        borrow_value,
        ctx(test)
       );

      let (collateral, loan, collateral_rewards_paid, loan_rewards_paid) = money_market::get_account_info<SUID>(&money_market_storage, alice);
 
      assert_eq(burn(coin_suid), borrow_value);
      assert_eq(burn(coin_ipx), 0); 
      assert_eq(collateral, 0);
      assert_eq(collateral_rewards_paid, 0);
      assert_eq(loan, borrow_value);
      assert_eq(loan_rewards_paid, 0);

      test::return_shared(suid_storage);
      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(money_market_storage); 
    };

    next_tx(test, alice);
    {
      let money_market_storage = test::take_shared<MoneyMarketStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);
      let suid_storage = test::take_shared<SuiDollarStorage>(test);

      let borrow_value = (5000 * SUID_DECIMALS_FACTOR as u64);

      let interest_rate_per_ms = money_market::get_borrow_rate_per_ms<SUID>(
        &money_market_storage,
        &interest_rate_model_storage
      );

      let timestame_increase = 83763618;

      clock::increment_for_testing(&mut clock_object, timestame_increase);

      let (_, _, _, _, _, _, _, _, _, _, _, _, _, total_principal, total_borrows, _) = money_market::get_market_info<SUID>(&money_market_storage);

      let accumulated_interest_rate = interest_rate_per_ms * timestame_increase;
      let new_total_borrows = total_borrows + (d_fmul(total_borrows, accumulated_interest_rate) as u64);

      // round up
      let added_principal = (((borrow_value as u256) * (total_principal as u256)) / (new_total_borrows as u256)) + 1;

      let (coin_suid, coin_ipx) = money_market::borrow_suid(
        &mut money_market_storage,
        &interest_rate_model_storage,
        &mut ipx_storage,
        &mut suid_storage,
        get_all_prices_potatoes(),
        &clock_object,
        borrow_value,
        ctx(test)
       );

      // 5 epoch rewards
      let loan_rewards_per_share = calculate_suid_market_rewards((timestame_increase as u256), 60000 * SUID_DECIMALS_FACTOR);

      let (collateral, loan, collateral_rewards_paid, loan_rewards_paid) = money_market::get_account_info<SUID>(&money_market_storage, alice);
      let new_principal = 60000 * SUID_DECIMALS_FACTOR + (added_principal as u256);

      assert_eq(burn(coin_suid), borrow_value);  
      assert_eq((burn(coin_ipx) as u256), loan_rewards_per_share * 60000); 
      assert_eq(collateral, 0);
      assert_eq((loan as u256), new_principal);
      assert_eq(collateral_rewards_paid, 0);
      assert_eq(loan_rewards_paid, loan_rewards_per_share * new_principal / SUID_DECIMALS_FACTOR);

      test::return_shared(suid_storage);
      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(money_market_storage); 
    };

    next_tx(test, alice);
    {
      let money_market_storage = test::take_shared<MoneyMarketStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);
      let suid_storage = test::take_shared<SuiDollarStorage>(test);

      let borrow_value = (1000 * SUID_DECIMALS_FACTOR as u64);

      let interest_rate_per_ms = money_market::get_borrow_rate_per_ms<SUID>(
        &money_market_storage,
        &interest_rate_model_storage,
      );

      let timestame_increase = 82761673839;

      clock::increment_for_testing(&mut clock_object, timestame_increase);

      let (_, _, _, _, _, _, _, _, _, _, prev_loan_rewards_per_share, _, _, total_principal, total_borrows, _) = money_market::get_market_info<SUID>(&money_market_storage);

      let accumulated_interest_rate = interest_rate_per_ms * timestame_increase;
      let new_total_borrows = total_borrows + (d_fmul(total_borrows, accumulated_interest_rate) as u64);

      // round up
      let added_principal = ((((borrow_value as u256) * (total_principal as u256)) / (new_total_borrows as u256)) + 1 as u64);

      let (_, prev_loan, _, prev_loan_rewards_paid) = money_market::get_account_info<SUID>(&money_market_storage, alice);

      let (coin_eth, coin_ipx) = money_market::borrow_suid(
        &mut money_market_storage,
        &interest_rate_model_storage,
        &mut ipx_storage,
        &mut suid_storage,
        get_all_prices_potatoes(),
        &clock_object,
        borrow_value,
        ctx(test)
       );

      // 5 epoch rewards
      let loan_rewards_per_share = calculate_suid_market_rewards((timestame_increase as u256), (total_principal as u256)) + prev_loan_rewards_per_share;

      let (collateral, loan, collateral_rewards_paid, loan_rewards_paid) = money_market::get_account_info<SUID>(&money_market_storage, alice);
      let new_principal = prev_loan + added_principal;

      assert_eq(burn(coin_eth), borrow_value);  
      assert_eq((burn(coin_ipx) as u256), (loan_rewards_per_share * (prev_loan as u256) / SUID_DECIMALS_FACTOR) - prev_loan_rewards_paid); 
      assert_eq(collateral, 0);
      assert_eq(loan, new_principal);
      assert_eq(collateral_rewards_paid, 0);
      assert_eq(loan_rewards_paid, loan_rewards_per_share * (new_principal as u256) / SUID_DECIMALS_FACTOR);

      test::return_shared(suid_storage);
      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(money_market_storage); 
    };

    clock::destroy_for_testing(clock_object);
    test::end(scenario);
  }


  #[test]
  #[expected_failure(abort_code = money_market::ipx_money_market::ERROR_MARKET_IS_PAUSED)]
  fun test_fail_borrow_suid_paused() {
    let scenario = scenario();

    let test = &mut scenario;

    init_test(test);
    let clock_object = clock::create_for_testing(ctx(test));

    let (alice, _) = people();

    next_tx(test, alice);
    {
      let money_market_storage = test::take_shared<MoneyMarketStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);

      burn(money_market::deposit<BTC>(
        &mut money_market_storage,
        &interest_rate_model_storage,
        &mut ipx_storage,
        &clock_object,
        mint<BTC>(10, BTC_DECIMALS, ctx(test)),
        ctx(test)
      ));

      money_market::enter_market<BTC>(&mut money_market_storage, ctx(test));

      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(money_market_storage);    
    };

    next_tx(test, alice);
   {
      let money_market_storage = test::take_shared<MoneyMarketStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);
      let suid_storage = test::take_shared<SuiDollarStorage>(test);
      let money_market_admin_cap = test::take_from_address<MoneyMarketAdminCap>(test, alice);

      money_market::enter_market<BTC>(&mut money_market_storage, ctx(test));
      money_market::pause_market<SUID>(&money_market_admin_cap, &mut money_market_storage);

      let (coin_suid, coin_ipx) = money_market::borrow_suid(
        &mut money_market_storage,
        &interest_rate_model_storage,
        &mut ipx_storage,
        &mut suid_storage,
        get_all_prices_potatoes(),
        &clock_object,
        (2 * SUID_DECIMALS_FACTOR as u64),
        ctx(test)
       );

       burn(coin_suid);
       burn(coin_ipx);

      test::return_to_address(alice, money_market_admin_cap);
      test::return_shared(suid_storage);
      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(money_market_storage); 
   };

    clock::destroy_for_testing(clock_object);
    test::end(scenario);
  }

  #[test]
  #[expected_failure(abort_code = money_market::ipx_money_market::ERROR_BORROW_CAP_LIMIT_REACHED)]
  fun test_fail_borrow_suid_cap_reached() {
    let scenario = scenario();

    let test = &mut scenario;

    init_test(test);
    let clock_object = clock::create_for_testing(ctx(test));

    let (alice, _) = people();

    next_tx(test, alice);
    {
      let money_market_storage = test::take_shared<MoneyMarketStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);

      burn(money_market::deposit<BTC>(
        &mut money_market_storage,
        &interest_rate_model_storage,
        &mut ipx_storage,
        &clock_object,
        mint<BTC>(10, BTC_DECIMALS, ctx(test)),
        ctx(test)
      ));

      money_market::enter_market<BTC>(&mut money_market_storage, ctx(test));

      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(money_market_storage);     
    };

    next_tx(test, alice);
   {
      let money_market_storage = test::take_shared<MoneyMarketStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);
      let suid_storage = test::take_shared<SuiDollarStorage>(test);
      let money_market_admin_cap = test::take_from_address<MoneyMarketAdminCap>(test, alice);

      money_market::enter_market<BTC>(&mut money_market_storage, ctx(test));
      money_market::set_borrow_cap<SUID>(&money_market_admin_cap, &mut money_market_storage, (SUID_DECIMALS_FACTOR as u64));

      let (coin_suid, coin_ipx) = money_market::borrow_suid(
        &mut money_market_storage,
        &interest_rate_model_storage,
        &mut ipx_storage,
        &mut suid_storage,
        get_all_prices_potatoes(),
        &clock_object,
        (1 + SUID_DECIMALS_FACTOR as u64),
        ctx(test)
       );

       burn(coin_suid);
       burn(coin_ipx);

      test::return_to_address(alice, money_market_admin_cap);
      test::return_shared(suid_storage);
      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(money_market_storage); 
   };

    clock::destroy_for_testing(clock_object);
    test::end(scenario);
  }

  #[test]
  #[expected_failure(abort_code = money_market::ipx_money_market::ERROR_USER_IS_SOLVENT)]
  fun test_fail_borrow_suid_insolvent() {
    let scenario = scenario();

    let test = &mut scenario;

    init_test(test);

    let (alice, _) = people();
    let clock_object = clock::create_for_testing(ctx(test));

    next_tx(test, alice);
    {
      let money_market_storage = test::take_shared<MoneyMarketStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);
      
      burn(money_market::deposit<BTC>(
        &mut money_market_storage,
        &interest_rate_model_storage,
        &mut ipx_storage,
        &clock_object,
        mint<BTC>(5, BTC_DECIMALS, ctx(test)),
        ctx(test)
      ));

      money_market::enter_market<BTC>(&mut money_market_storage, ctx(test));

      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(money_market_storage); 
    };

    next_tx(test, alice);
   {
      let money_market_storage = test::take_shared<MoneyMarketStorage>(test);
      let interest_rate_model_storage = test::take_shared<InterestRateModelStorage>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);
      let suid_storage = test::take_shared<SuiDollarStorage>(test);
      let money_market_admin_cap = test::take_from_address<MoneyMarketAdminCap>(test, alice);

      money_market::enter_market<BTC>(&mut money_market_storage, ctx(test));

      let (coin_suid, coin_ipx) = money_market::borrow_suid(
        &mut money_market_storage,
        &interest_rate_model_storage,
        &mut ipx_storage,
        &mut suid_storage,
        get_all_prices_potatoes(),
        &clock_object,
        (70001 * SUID_DECIMALS_FACTOR as u64),
        ctx(test)
       );

       burn(coin_suid);
       burn(coin_ipx);

      test::return_to_address(alice, money_market_admin_cap);
      test::return_shared(suid_storage);
      test::return_shared(ipx_storage);
      test::return_shared(interest_rate_model_storage);
      test::return_shared(money_market_storage); 
   };

    clock::destroy_for_testing(clock_object);
    test::end(scenario);
  }

  // utils

  public fun calculate_btc_market_rewards(timestamp_delta: u256, total_principal: u256): u256 {
    ((timestamp_delta * INITIAL_IPX_PER_MS * 500) / 2600/ 2) * BTC_DECIMALS_FACTOR / total_principal  
  }

 public fun calculate_eth_market_rewards(timestamp_delta: u256, total_principal: u256): u256 {
    ((timestamp_delta * INITIAL_IPX_PER_MS * 700) / 2600/ 2) * ETH_DECIMALS_FACTOR / total_principal
  }

  public fun calculate_suid_market_rewards(num_of_epochs: u256, total_principal: u256): u256 {
    ((num_of_epochs * INITIAL_IPX_PER_MS * 500) / 2600) * SUID_DECIMALS_FACTOR / total_principal
  }

  public fun get_all_prices_potatoes(): vector<PricePotato> {
    let btc_price = get_price_for_testing<BTC>(0, 0, 0, 0, INITIAL_BTC_PRICE);
    let eth_price = get_price_for_testing<ETH>(0, 0, 0, 0,  INITIAL_ETH_PRICE);
    let ada_price = get_price_for_testing<ADA>(0, 0, 0, 0,  INITIAL_ADA_PRICE);

    let price_potato_vector = vector::empty<PricePotato>();

    vector::push_back(&mut price_potato_vector, btc_price);
    vector::push_back(&mut price_potato_vector, eth_price);
    vector::push_back(&mut price_potato_vector, ada_price);

    price_potato_vector
  }
} 

