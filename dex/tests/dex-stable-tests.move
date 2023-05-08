#[test_only]
module dex::dex_stable_tests {

    use sui::coin::{Self, mint_for_testing as mint, burn_for_testing as burn, CoinMetadata};
    use sui::test_scenario::{Self as test, Scenario, next_tx, ctx};
    use sui::test_utils::{assert_eq};
    use sui::object;
    use sui::clock;

    use dex::core::{Self as dex, DEXStorage as Storage, DEXAdminCap, LPCoin};
    use dex::curve::{Stable};
    use library::test_utils::{people, scenario};
    use library::math::{sqrt_u256};
    use library::usdc::{Self, USDC};
    use library::usdt::{Self, USDT};

    const USDT_DECIMAL_SCALAR: u64 = 1000000000; // 9 decimals
    const INITIAL_USDT_VALUE: u64 = 100 * 1000000000; //100 * 1e9
    const USDC_DECIMAL_SCALAR: u64 = 1000000; // 6 decimals
    const INITIAL_USDC_VALUE: u64 = 100 * 1000000;
    const ZERO_ACCOUNT: address = @0x0;
    const DESCALE_FACTOR: u256 =  1000000000; //1e9 


    fun test_create_pool_(test: &mut Scenario) {
      let (alice, _) = people();
      
      let initial_k = dex::get_k<Stable>(INITIAL_USDC_VALUE, INITIAL_USDT_VALUE, USDC_DECIMAL_SCALAR, USDT_DECIMAL_SCALAR);
      let lp_coin_initial_user_balance = (sqrt_u256(sqrt_u256((INITIAL_USDC_VALUE as u256) * (INITIAL_USDT_VALUE as u256))) as u64);
      let minimum_liquidity = dex::get_minimum_liquidity();

      next_tx(test, alice);
      {
        dex::init_for_testing(ctx(test));
        usdc::init_for_testing(ctx(test));
        usdt::init_for_testing(ctx(test));
      };
      
      let clock_object = clock::create_for_testing(ctx(test));

      next_tx(test, alice);
      {
        let storage = test::take_shared<Storage>(test);
        let usdc_coin_metadata = test::take_immutable<CoinMetadata<USDC>>(test);
        let usdt_coin_metadata = test::take_immutable<CoinMetadata<USDT>>(test);

        let lp_coin = dex::create_s_pool(
          &mut storage,
          &clock_object,
          mint<USDC>(INITIAL_USDC_VALUE, ctx(test)),
          mint<USDT>(INITIAL_USDT_VALUE, ctx(test)),
          &usdc_coin_metadata,
          &usdt_coin_metadata,
          ctx(test)
        );

        assert!(burn(lp_coin) == (lp_coin_initial_user_balance as u64), 0);
        test::return_shared(storage);
        test::return_immutable(usdc_coin_metadata);
        test::return_immutable(usdt_coin_metadata);
      };

      next_tx(test, alice);
      {
        let storage = test::take_shared<Storage>(test);
        let pool = dex::borrow_pool<Stable, USDC, USDT>(&storage);
        let (usdc_reserves, usdt_reserves, supply) = dex::get_amounts(pool);
        let k_last = dex::get_k_last<Stable, USDC, USDT>(&storage);
        let (decimals_x, decimals_y) = dex::get_pool_metadata<Stable, USDC, USDT>(&storage);

        assert!(supply == lp_coin_initial_user_balance + minimum_liquidity, 0);
        assert!(usdc_reserves == INITIAL_USDC_VALUE, 0);
        assert!(usdt_reserves == INITIAL_USDT_VALUE, 0);
        assert!(k_last == initial_k, 0);
        assert!(decimals_x == USDC_DECIMAL_SCALAR, 0);
        assert!(decimals_y == USDT_DECIMAL_SCALAR, 0);

        test::return_shared(storage);
      };

      clock::destroy_for_testing(clock_object);
    }

    #[test]
    fun test_create_pool() {
        let scenario = scenario();
        test_create_pool_(&mut scenario);
        test::end(scenario);
    }

    fun test_swap_token_x_(test: &mut Scenario) {
       test_create_pool_(test);

       let (_, bob) = people();
        let clock_object = clock::create_for_testing(ctx(test));

       next_tx(test, bob);
       {
        let storage = test::take_shared<Storage>(test);

        let usdc_amount = INITIAL_USDC_VALUE / 10;

        let pool = dex::borrow_pool<Stable, USDC, USDT>(&storage);
        let (usdc_reserves, usdt_reserves, _) = dex::get_amounts(pool);

        let token_in_amount = usdc_amount - ((usdc_amount * 30) / 10000);
        // 9086776671
        let v_usdt_amount_received = (usdt_reserves * token_in_amount) / (token_in_amount + usdc_reserves);
        // calculated off chain to save time
        let s_usdt_amount_received = 9990015154;


        let usdt = dex::swap_token_x<Stable, USDC, USDT>(
          &mut storage,
          &clock_object,
          mint<USDC>(usdc_amount, ctx(test)),
          0,
          ctx(test)
        );

        assert_eq(burn(usdt), s_usdt_amount_received);
        // 10% less slippage
        assert!(s_usdt_amount_received > v_usdt_amount_received, 0);
    
        test::return_shared(storage);
       };

      clock::destroy_for_testing(clock_object);
    }

    #[test]
    fun test_swap_token_x() {
        let scenario = scenario();
        test_swap_token_x_(&mut scenario);
        test::end(scenario);
    }

    fun test_swap_token_y_(test: &mut Scenario) {
       test_create_pool_(test);

       let (_, bob) = people();
       let clock_object = clock::create_for_testing(ctx(test));

       next_tx(test, bob);
       {
        let storage = test::take_shared<Storage>(test);

        let usdt_amount = INITIAL_USDT_VALUE / 10;

        let pool = dex::borrow_pool<Stable, USDC, USDT>(&storage);
        let (usdc_reserves, usdt_reserves, _) = dex::get_amounts(pool);

        let token_in_amount = usdt_amount - ((usdt_amount * 50) / 100000);
        // 9086776
        let v_usdc_amount_received = (usdc_reserves * token_in_amount) / (token_in_amount + usdt_reserves);
        // calculated off chain to save time
        let s_usdc_amount_received = 9990015;


        let usdc = dex::swap_token_y<Stable, USDC, USDT>(
          &mut storage,
          &clock_object,
          mint<USDT>(usdt_amount, ctx(test)),
          0,
          ctx(test)
        );

        assert_eq(burn(usdc), s_usdc_amount_received);
        // 10% less slippage
        assert!(s_usdc_amount_received > v_usdc_amount_received, 0);
        
        test::return_shared(storage);
       };
      
      clock::destroy_for_testing(clock_object);
    }

    #[test]
    fun test_swap_token_y() {
        let scenario = scenario();
        test_swap_token_y_(&mut scenario);
        test::end(scenario);
    }

    fun test_add_liquidity_(test: &mut Scenario) {
        test_create_pool_(test);
        remove_fee(test);

        let (_, bob) = people();

        let usdt_value = INITIAL_USDT_VALUE / 10;
        let usdc_value = INITIAL_USDC_VALUE / 10;

        let clock_object = clock::create_for_testing(ctx(test));

        next_tx(test, bob);
        {
        let storage = test::take_shared<Storage>(test);

        let pool = dex::borrow_pool<Stable, USDC, USDT>(&storage);
        let (_, _, supply) = dex::get_amounts(pool);

        let lp_coin = dex::add_liquidity<Stable, USDC, USDT>(
          &mut storage,
          &clock_object,
          mint<USDC>(usdc_value, ctx(test)),
          mint<USDT>(usdt_value, ctx(test)),
          0,
          ctx(test)
          );

        let pool = dex::borrow_pool<Stable, USDC, USDT>(&storage); 
        let (usdc_reserves, usdt_reserves, _) = dex::get_amounts(pool); 

        assert!(burn(lp_coin)== supply / 10, 0);
        assert!(usdc_reserves == INITIAL_USDC_VALUE + usdc_value, 0);
        assert!(usdt_reserves == INITIAL_USDT_VALUE + usdt_value, 0);
        
        test::return_shared(storage);
        };

        clock::destroy_for_testing(clock_object);   
    }

    #[test]
    fun test_add_liquidity() {
        let scenario = scenario();
        test_add_liquidity_(&mut scenario);
        test::end(scenario);      
    }

    fun test_remove_liquidity_(test: &mut Scenario) {
        test_create_pool_(test);
        remove_fee(test);

        let (_, bob) = people();

        let usdt_value = INITIAL_USDT_VALUE / 10;
        let usdc_value = INITIAL_USDC_VALUE / 10;
        let clock_object = clock::create_for_testing(ctx(test));

        next_tx(test, bob);
        {
          let storage = test::take_shared<Storage>(test);

          let lp_coin = dex::add_liquidity<Stable, USDC, USDT>(
            &mut storage,
            &clock_object,
            mint<USDC>(usdc_value, ctx(test)),
            mint<USDT>(usdt_value, ctx(test)),
            0,
            ctx(test)
          );

          let pool = dex::borrow_pool<Stable, USDC, USDT>(&storage);
          let (usdc_reserves_1, usdt_reserves_1, supply_1) = dex::get_amounts(pool);

          let lp_coin_value = coin::value(&lp_coin);

          let (usdc, usdt) = dex::remove_liquidity(
              &mut storage,
              &clock_object,
              lp_coin,
              0,
              0,
              ctx(test)
          );

          let pool = dex::borrow_pool<Stable, USDC, USDT>(&storage);
          let (usdc_reserves_2, usdt_reserves_2, supply_2) = dex::get_amounts(pool);

          // rounding issues
          assert_eq(burn(usdt), 9999354495);
          assert_eq(burn(usdc), 9999354);
          assert_eq(supply_1, supply_2 + lp_coin_value);
          assert_eq(usdc_reserves_1, usdc_reserves_2 + 9999354);
          assert_eq(usdt_reserves_1, usdt_reserves_2 + 9999354495);

          test::return_shared(storage);
        };

      clock::destroy_for_testing(clock_object);  
    }

    #[test]
    fun test_remove_liquidity() {
        let scenario = scenario();
        test_remove_liquidity_(&mut scenario);
        test::end(scenario);
    }

    fun test_add_liquidity_with_fee_(test: &mut Scenario) {
        test_create_pool_(test);

        let clock_object = clock::create_for_testing(ctx(test));
        let usdt_value = INITIAL_USDT_VALUE / 10;
        let usdc_value = INITIAL_USDC_VALUE / 10;

       let (_, bob) = people();
        
       next_tx(test, bob);
       // Get fees
       {
        let storage = test::take_shared<Storage>(test);
        
        let r1 = dex::swap_token_x<Stable, USDC, USDT>(
          &mut storage,
          &clock_object,
          mint<USDC>(INITIAL_USDC_VALUE / 2, ctx(test)),
          0,
          ctx(test)
        );

        let r2 = dex::swap_token_y<Stable, USDC, USDT>(
          &mut storage,
          &clock_object,
          mint<USDT>(INITIAL_USDT_VALUE / 2, ctx(test)),
          0,
          ctx(test)
        );

        let r3 = dex::swap_token_x<Stable, USDC, USDT>(
          &mut storage,
          &clock_object,
          mint<USDC>(INITIAL_USDC_VALUE / 2, ctx(test)),
          0,
          ctx(test)
        );

        let r4 = dex::swap_token_y<Stable, USDC, USDT>(
          &mut storage,
          &clock_object,
          mint<USDT>(INITIAL_USDT_VALUE / 2, ctx(test)),
          0,
          ctx(test)
        );

        assert!(burn(r1) != 0, 0);
        assert!(burn(r2) != 0, 0);
        assert!(burn(r3) != 0, 0);
        assert!(burn(r4) != 0, 0);

        test::return_shared(storage); 
       };

       next_tx(test, bob);
       {
        let storage = test::take_shared<Storage>(test);
  
        let pool = dex::borrow_pool<Stable, USDC, USDT>(&storage);
        let (usdc_reserves_1, usdt_reserves_1, supply_1) = dex::get_amounts(pool);
        let k_last = dex::get_k_last<Stable, USDC, USDT>(&mut storage);
        
        let root_k = sqrt_u256(dex::get_k<Stable>(usdc_reserves_1, usdt_reserves_1, USDC_DECIMAL_SCALAR, USDT_DECIMAL_SCALAR));
        let root_k_last = sqrt_u256(k_last);
        let numerator = (supply_1 as u256) * (root_k - root_k_last);
        let denominator  = (root_k * 5) + root_k_last;
        let fee = (numerator / denominator as u64);

        let lp_coin = dex::add_liquidity<Stable, USDC, USDT>(
          &mut storage,
          &clock_object,
          mint<USDC>(usdc_value, ctx(test)),
          mint<USDT>(usdt_value, ctx(test)),
          0,
          ctx(test)
        );

        let pool = dex::borrow_pool<Stable, USDC, USDT>(&storage);
        let (_, _, supply_2) = dex::get_amounts(pool);

        assert!(fee > 0, 0);
        assert!(burn(lp_coin) + fee + supply_1 == supply_2, 0);
    
        test::return_shared(storage);
       };

      clock::destroy_for_testing(clock_object);
    }

    #[test]
    fun test_add_liquidity_with_fee() {
        let scenario = scenario();
        test_add_liquidity_with_fee_(&mut scenario);
        test::end(scenario);
    }

    fun test_remove_liquidity_with_fee_(test: &mut Scenario) {
      test_create_pool_(test);
       let clock_object = clock::create_for_testing(ctx(test));
       let (_, bob) = people();
        
       next_tx(test, bob);
       {
        let storage = test::take_shared<Storage>(test);

        let r1 = dex::swap_token_x<Stable, USDC, USDT>(
          &mut storage,
          &clock_object,
          mint<USDC>(INITIAL_USDC_VALUE / 2, ctx(test)),
          0,
          ctx(test)
        );

        let r2 = dex::swap_token_y<Stable, USDC, USDT>(
          &mut storage,
          &clock_object,
          mint<USDT>(INITIAL_USDT_VALUE / 2, ctx(test)),
          0,
          ctx(test)
        );

        let r3 = dex::swap_token_x<Stable, USDC, USDT>(
          &mut storage,
          &clock_object,
          mint<USDC>(INITIAL_USDC_VALUE / 2, ctx(test)),
          0,
          ctx(test)
        );

        let r4 = dex::swap_token_y<Stable, USDC, USDT>(
          &mut storage,
          &clock_object,
          mint<USDT>(INITIAL_USDT_VALUE / 2, ctx(test)),
          0,
          ctx(test)
        );

        assert!(burn(r1) != 0, 0);
        assert!(burn(r2) != 0, 0);
        assert!(burn(r3) != 0, 0);
        assert!(burn(r4) != 0, 0);

        test::return_shared(storage); 
       };

       next_tx(test, bob);
       {
        let storage = test::take_shared<Storage>(test);

        let pool = dex::borrow_pool<Stable, USDC, USDT>(&storage);
        let (usdc_reserves_1, usdt_reserves_1, supply_1) = dex::get_amounts(pool);
        let k_last = dex::get_k_last<Stable, USDC, USDT>(&mut storage);

        let root_k = sqrt_u256(dex::get_k<Stable>(usdc_reserves_1, usdt_reserves_1, USDC_DECIMAL_SCALAR, USDT_DECIMAL_SCALAR));
        let root_k_last = sqrt_u256(k_last);
        let numerator = (supply_1 as u256) * (root_k - root_k_last);
        let denominator  = (root_k * 5) + root_k_last;
        let fee = (numerator / denominator as u64);

        let (ether, usdc) = dex::remove_liquidity<Stable, USDC, USDT>(
          &mut storage,
          &clock_object,
          mint<LPCoin<Stable, USDC, USDT>>(supply_1 / 10, ctx(test)),
          0,
          0,
          ctx(test)
        );

        burn(ether);
        burn(usdc);

        let pool = dex::borrow_pool<Stable, USDC, USDT>(&storage);
        let (_, _, supply_2) = dex::get_amounts(pool);

        assert!(fee > 0, 0);
        assert!(supply_2 == supply_1 + fee - supply_1 / 10, 0);

        test::return_shared(storage);
       };

       clock::destroy_for_testing(clock_object);
    }

    #[test]
    fun test_remove_liquidity_with_fee() {
        let scenario = scenario();
        test_remove_liquidity_with_fee_(&mut scenario);
        test::end(scenario);
    }

      fun test_flash_loan_(test: &mut Scenario) {
      test_create_pool_(test);

      let (_, bob) = people();
      let clock_object = clock::create_for_testing(ctx(test));
      
      next_tx(test, bob);
      {
        let storage = test::take_shared<Storage>(test);

        let (receipt, usdc, usdt) = dex::flash_loan<Stable, USDC, USDT>(&mut storage, INITIAL_USDC_VALUE / 2, INITIAL_USDT_VALUE / 3, ctx(test));

        let pool = dex::borrow_pool<Stable, USDC, USDT>(&storage);

        let (recipet_pool_id, repay_amount_x, repay_amount_y, _) = dex::get_receipt_data(&receipt);
        let (fee, precision) = dex::get_flash_loan_fee_percent();

        let amount_to_mint_x = (((INITIAL_USDC_VALUE / 2 as u256) * fee / precision) as u64);
        let amount_to_mint_y = (((INITIAL_USDT_VALUE / 3 as u256) * fee / precision) as u64);

        assert!(coin::value(&usdc) == INITIAL_USDC_VALUE / 2, 0);
        assert!(coin::value(&usdt) == INITIAL_USDT_VALUE / 3, 0);
        assert!(object::id(pool) == recipet_pool_id, 0);
        assert!(repay_amount_x == INITIAL_USDC_VALUE / 2 + amount_to_mint_x, 0);
        assert!(repay_amount_y == INITIAL_USDT_VALUE / 3 + amount_to_mint_y, 0);
        assert!(dex::is_pool_locked<Stable, USDC, USDT>(&storage), 0);

        coin::join(&mut usdc, mint<USDC>(amount_to_mint_x, ctx(test)));
        coin::join(&mut usdt, mint<USDT>(amount_to_mint_y, ctx(test)));

        dex::repay_flash_loan(
          &mut storage,
          &clock_object,
          receipt,
          usdc,
          usdt
        );
        assert!(!dex::is_pool_locked<Stable, USDC, USDT>(&storage), 0);

        test::return_shared(storage);
      };

      clock::destroy_for_testing(clock_object);
    }

    #[test]
    fun test_flash_loan() {
        let scenario = scenario();
        test_flash_loan_(&mut scenario);
        test::end(scenario);
    }

  #[test]
  #[expected_failure(abort_code = dex::core::ERROR_CREATE_PAIR_ZERO_VALUE)]
  fun test_create_pool_zero_value_y_error() {
      let scenario = scenario();
      let (alice, _) = people();
      let test = &mut scenario;
      let clock_object = clock::create_for_testing(ctx(test));

      next_tx(test, alice);
      {
        dex::init_for_testing(ctx(test));
        usdc::init_for_testing(ctx(test));
        usdt::init_for_testing(ctx(test));      
      };

      next_tx(test, alice);
      {
        let storage = test::take_shared<Storage>(test);  
        let usdc_coin_metadata = test::take_immutable<CoinMetadata<USDC>>(test);
        let usdt_coin_metadata = test::take_immutable<CoinMetadata<USDT>>(test);

        burn(dex::create_s_pool(
          &mut storage,
          &clock_object,
          mint<USDC>(INITIAL_USDC_VALUE, ctx(test)),
          mint<USDT>(0, ctx(test)),
          &usdc_coin_metadata,
          &usdt_coin_metadata,
          ctx(test)
        ));

        test::return_shared(storage);
        test::return_immutable(usdc_coin_metadata);
        test::return_immutable(usdt_coin_metadata);
      };
      
      clock::destroy_for_testing(clock_object);
      test::end(scenario);
  }

  #[test]
  #[expected_failure(abort_code = dex::core::ERROR_CREATE_PAIR_ZERO_VALUE)]
  fun test_create_pool_zero_value_x_error() {
      let scenario = scenario();
      let (alice, _) = people();
      let test = &mut scenario;
      let clock_object = clock::create_for_testing(ctx(test));

      next_tx(test, alice);
      {
        dex::init_for_testing(ctx(test));
        usdc::init_for_testing(ctx(test));
        usdt::init_for_testing(ctx(test));          
      };

      next_tx(test, alice);
      {
        let storage = test::take_shared<Storage>(test);      
        let usdc_coin_metadata = test::take_immutable<CoinMetadata<USDC>>(test);
        let usdt_coin_metadata = test::take_immutable<CoinMetadata<USDT>>(test);

        burn(dex::create_s_pool(
          &mut storage,
          &clock_object,
          mint<USDC>(0, ctx(test)),
          mint<USDT>(INITIAL_USDT_VALUE, ctx(test)),
          &usdc_coin_metadata,
          &usdt_coin_metadata,
          ctx(test)
        ));

        test::return_shared(storage);     
        test::return_immutable(usdc_coin_metadata);
        test::return_immutable(usdt_coin_metadata);
      };
      
      clock::destroy_for_testing(clock_object);
      test::end(scenario);
  }

  #[test]
  #[expected_failure(abort_code = dex::core::ERROR_UNSORTED_COINS)]
  fun test_create_pool_zero_unsorted_error() {
      let scenario = scenario();
      let (alice, _) = people();
      let test = &mut scenario;
      let clock_object = clock::create_for_testing(ctx(test));

      next_tx(test, alice);
      {
        dex::init_for_testing(ctx(test));
        usdc::init_for_testing(ctx(test));
        usdt::init_for_testing(ctx(test));
      };

      next_tx(test, alice);
      {
        let storage = test::take_shared<Storage>(test);
        let usdc_coin_metadata = test::take_immutable<CoinMetadata<USDC>>(test);
        let usdt_coin_metadata = test::take_immutable<CoinMetadata<USDT>>(test);

        burn(dex::create_s_pool(
          &mut storage,
          &clock_object,
          mint<USDT>(INITIAL_USDT_VALUE, ctx(test)),
          mint<USDC>(INITIAL_USDC_VALUE, ctx(test)),
          &usdt_coin_metadata,
          &usdc_coin_metadata,
          ctx(test)
        ));

        test::return_shared(storage);
        test::return_immutable(usdc_coin_metadata);
        test::return_immutable(usdt_coin_metadata);
      };

      clock::destroy_for_testing(clock_object);
      
      test::end(scenario);
  }

  #[test]
  #[expected_failure(abort_code = dex::core::ERROR_ADD_LIQUIDITY_ZERO_AMOUNT)]
  fun test_add_liquidity_zero_amount_x_error() {
      let scenario = scenario();
      let (alice, _) = people();
      let test = &mut scenario;
      let clock_object = clock::create_for_testing(ctx(test));
      test_create_pool_(test);
      
      let usdt_value = INITIAL_USDT_VALUE / 10;
      let usdc_value = 0;

      next_tx(test, alice);
      {
        let storage = test::take_shared<Storage>(test);
        
        burn(dex::add_liquidity<Stable, USDC, USDT>(
          &mut storage,
          &clock_object,
          mint<USDC>(usdc_value, ctx(test)),
          mint<USDT>(usdt_value, ctx(test)),
          0,
          ctx(test)
        ));

        test::return_shared(storage);
      }; 

      clock::destroy_for_testing(clock_object);
      test::end(scenario);
  }

  #[test]
  #[expected_failure(abort_code = dex::core::ERROR_ADD_LIQUIDITY_ZERO_AMOUNT)]
  fun test_add_liquidity_zero_amount_y_error() {
      let scenario = scenario();
      let (alice, _) = people();
      let test = &mut scenario;

      test_create_pool_(test);
      let clock_object = clock::create_for_testing(ctx(test));
      let usdt_value = 0;
      let usdc_value = INITIAL_USDC_VALUE / 10;

      next_tx(test, alice);
      {
        let storage = test::take_shared<Storage>(test);

        burn(dex::add_liquidity<Stable, USDC, USDT>(
          &mut storage,
          &clock_object,
          mint<USDC>(usdc_value, ctx(test)),
          mint<USDT>(usdt_value, ctx(test)),
          0,
          ctx(test)
        ));

       test::return_shared(storage);
      }; 

      clock::destroy_for_testing(clock_object);
      test::end(scenario);
  }

  #[test]
  #[expected_failure(abort_code = dex::core::ERROR_REMOVE_LIQUIDITY_ZERO_AMOUNT)]
  fun test_remove_liquidity_zero_amount_error() {
      let scenario = scenario();
      let (alice, _) = people();
      let test = &mut scenario;

      test_create_pool_(test);
      let clock_object = clock::create_for_testing(ctx(test));
      
      next_tx(test, alice);
      {
        let storage = test::take_shared<Storage>(test);

        let (usdc, usdt) = dex::remove_liquidity<Stable, USDC, USDT>(
          &mut storage,
          &clock_object,
          mint<LPCoin<Stable, USDC, USDT>>(0, ctx(test)),
          0,
          0,
          ctx(test)
        );

        burn(usdc);
        burn(usdt);

        test::return_shared(storage);
      };

      clock::destroy_for_testing(clock_object);
      test::end(scenario);
  }

  #[test]
  #[expected_failure(abort_code = dex::core::ERROR_REMOVE_LIQUIDITY_X_AMOUNT)]
  fun test_remove_liquidity_x_amount_error() {
      let scenario = scenario();
      let (alice, _) = people();
      let test = &mut scenario;

      test_create_pool_(test);
      remove_fee(test);
      
      let usdt_value = INITIAL_USDT_VALUE / 10;
      let usdc_value = INITIAL_USDC_VALUE / 10;
      let clock_object = clock::create_for_testing(ctx(test));

       next_tx(test, alice);
        {
          let storage = test::take_shared<Storage>(test);

          let lp_coin = dex::add_liquidity<Stable, USDC, USDT>(
            &mut storage,
            &clock_object,
            mint<USDC>(usdc_value, ctx(test)),
            mint<USDT>(usdt_value, ctx(test)),
            0,
            ctx(test)
          );

          let (usdc, usdt) = dex::remove_liquidity(
              &mut storage,
              &clock_object,
              lp_coin,
              usdc_value,
              0,
              ctx(test)
          );

          burn(usdc);
          burn(usdt);
     
          test::return_shared(storage);
        };

      clock::destroy_for_testing(clock_object);  
      test::end(scenario);
  }

  #[test]
  #[expected_failure(abort_code = dex::core::ERROR_REMOVE_LIQUIDITY_Y_AMOUNT)]
  fun test_remove_liquidity_y_amount_error() {
      let scenario = scenario();
      let (alice, _) = people();
      let test = &mut scenario;

      test_create_pool_(test);
      remove_fee(test);
      
      let usdt_value = INITIAL_USDT_VALUE / 10;
      let usdc_value = INITIAL_USDC_VALUE / 10;
      let clock_object = clock::create_for_testing(ctx(test));

       next_tx(test, alice);
        {
          let storage = test::take_shared<Storage>(test);

          let lp_coin = dex::add_liquidity<Stable, USDC, USDT>(
            &mut storage,
            &clock_object,
            mint<USDC>(usdc_value, ctx(test)),
            mint<USDT>(usdt_value, ctx(test)),
            0,
            ctx(test)
          );

          let (usdc, usdt) = dex::remove_liquidity(
              &mut storage,
              &clock_object,
              lp_coin,
              0,
              usdt_value,
              ctx(test)
          );

          burn(usdc);
          burn(usdt);
        
          test::return_shared(storage);
        };
      clock::destroy_for_testing(clock_object);
      test::end(scenario);
    }

  #[test]
  #[expected_failure(abort_code = dex::core::ERROR_ZERO_VALUE_SWAP)]
  fun test_swap_token_x_zero_value_error() {
      let scenario = scenario();
      let (alice, _) = people();
      let test = &mut scenario;

      test_create_pool_(test);
      remove_fee(test);
      let clock_object = clock::create_for_testing(ctx(test));

      next_tx(test, alice);
       {
        let storage = test::take_shared<Storage>(test);
        
        let usdc_amount = INITIAL_USDC_VALUE / 10;

        let pool = dex::borrow_pool<Stable, USDC, USDT>(&storage);
        let (usdc_reserves, usdt_reserves, _) = dex::get_amounts(pool);

        let token_in_amount = usdc_amount - ((usdc_amount * 30) / 10000);
        // 9086776671
        let v_usdt_amount_received = (usdt_reserves * token_in_amount) / (token_in_amount + usdc_reserves);
        // calculated off chain to save time
        let s_usdt_amount_received = 9990015154;


        let usdt = dex::swap_token_x<Stable, USDC, USDT>(
          &mut storage,
          &clock_object,
          mint<USDC>(0, ctx(test)),
          0,
          ctx(test)
        );

        assert!(burn(usdt) == s_usdt_amount_received, 0);
        // 10% less slippage
        assert!(s_usdt_amount_received > v_usdt_amount_received, 0);
       
        test::return_shared(storage);
      };
      clock::destroy_for_testing(clock_object);
      test::end(scenario);
  }

  #[test]
  #[expected_failure(abort_code = dex::core::ERROR_SLIPPAGE)]
  fun test_swap_token_x_slippage_error() {
      let scenario = scenario();
      let (alice, _) = people();
      let test = &mut scenario;

      test_create_pool_(test);
      remove_fee(test);
      
      let clock_object = clock::create_for_testing(ctx(test));
      
      next_tx(test, alice);
       {
        let storage = test::take_shared<Storage>(test); 

        let usdc_amount = INITIAL_USDC_VALUE / 10;

        let pool = dex::borrow_pool<Stable, USDC, USDT>(&storage);
        let (usdc_reserves, usdt_reserves, _) = dex::get_amounts(pool);

        let token_in_amount = usdc_amount - ((usdc_amount * 30) / 10000);
        // 9086776671
        let v_usdt_amount_received = (usdt_reserves * token_in_amount) / (token_in_amount + usdc_reserves);
        // calculated off chain to save time
        let s_usdt_amount_received = 9990015154;


        let usdt = dex::swap_token_x<Stable, USDC, USDT>(
          &mut storage,
          &clock_object,
          mint<USDC>(token_in_amount, ctx(test)),
          s_usdt_amount_received + 1,
          ctx(test)
        );

        assert!(burn(usdt) == s_usdt_amount_received, 0);
        // 10% less slippage
        assert!(s_usdt_amount_received > v_usdt_amount_received, 0);
      
        test::return_shared(storage);
      };
      
      clock::destroy_for_testing(clock_object);
      test::end(scenario);
  }

  #[test]
  #[expected_failure(abort_code = dex::core::ERROR_ZERO_VALUE_SWAP)]
  fun test_swap_token_y_zero_value_error() {
      let scenario = scenario();
      let (alice, _) = people();
      let test = &mut scenario;

      test_create_pool_(test);
      remove_fee(test);
      let clock_object = clock::create_for_testing(ctx(test));

      next_tx(test, alice);
       {
        let storage = test::take_shared<Storage>(test);

        let usdt_amount = INITIAL_USDT_VALUE / 10;

        let pool = dex::borrow_pool<Stable, USDC, USDT>(&storage);
        let (usdc_reserves, usdt_reserves, _) = dex::get_amounts(pool);

        let token_in_amount = usdt_amount - ((usdt_amount * 50) / 100000);
        // 9086776
        let v_usdc_amount_received = (usdc_reserves * token_in_amount) / (token_in_amount + usdt_reserves);
        // calculated off chain to save time
        let s_usdc_amount_received = 9990015;


        let usdc = dex::swap_token_y<Stable, USDC, USDT>(
          &mut storage,
          &clock_object,
          mint<USDT>(0, ctx(test)),
          0,
          ctx(test)
        );

        assert!(burn(usdc) == s_usdc_amount_received, 0);
        // 10% less slippage
        assert!(s_usdc_amount_received > v_usdc_amount_received, 0);
        
        test::return_shared(storage);
       };
      
      clock::destroy_for_testing(clock_object);
      test::end(scenario);
  }

  #[test]
  #[expected_failure(abort_code = dex::core::ERROR_SLIPPAGE)]
  fun test_swap_token_y_slippage_error() {
      let scenario = scenario();
      let (alice, _) = people();
      let test = &mut scenario;
      let clock_object = clock::create_for_testing(ctx(test));

      test_create_pool_(test);
      remove_fee(test);
      
      next_tx(test, alice);
       {
        let storage = test::take_shared<Storage>(test);

        let usdt_amount = INITIAL_USDT_VALUE / 10;

        let pool = dex::borrow_pool<Stable, USDC, USDT>(&storage);
        let (usdc_reserves, usdt_reserves, _) = dex::get_amounts(pool);

        let token_in_amount = usdt_amount - ((usdt_amount * 50) / 100000);
        // 9086776
        let v_usdc_amount_received = (usdc_reserves * token_in_amount) / (token_in_amount + usdt_reserves);
        // calculated off chain to save time
        let s_usdc_amount_received = 9990015;


        let usdc = dex::swap_token_y<Stable, USDC, USDT>(
          &mut storage,
          &clock_object,
          mint<USDT>(token_in_amount, ctx(test)),
          s_usdc_amount_received + 1,
          ctx(test)
        );

        assert!(burn(usdc) == s_usdc_amount_received, 0);
        // 10% less slippage
        assert!(s_usdc_amount_received > v_usdc_amount_received, 0);
       
        test::return_shared(storage);
       };

      clock::destroy_for_testing(clock_object);
      test::end(scenario);
  }

  #[test]
  #[expected_failure(abort_code = dex::core::ERROR_NOT_ENOUGH_LIQUIDITY_TO_LEND)]
  fun test_flash_loan_not_enough_liquidity_error() {
       let scenario = scenario();
      let test = &mut scenario;

      test_create_pool_(test);
      let clock_object = clock::create_for_testing(ctx(test));

      let (_, bob) = people();
        
      next_tx(test, bob);
      {
        let storage = test::take_shared<Storage>(test);

        let (receipt, usdc, usdt) = dex::flash_loan<Stable, USDC, USDT>(&mut storage, INITIAL_USDC_VALUE + 1, INITIAL_USDT_VALUE / 3, ctx(test));

        let pool = dex::borrow_pool<Stable, USDC, USDT>(&storage);

        let (recipet_pool_id, repay_amount_x, repay_amount_y, _) = dex::get_receipt_data(&receipt);
        let (fee, precision) = dex::get_flash_loan_fee_percent();

        let amount_to_mint_x = (((INITIAL_USDC_VALUE / 2 as u256) * fee / precision) as u64);
        let amount_to_mint_y = (((INITIAL_USDT_VALUE / 3 as u256) * fee / precision) as u64);

        assert!(coin::value(&usdc) == INITIAL_USDC_VALUE / 2, 0);
        assert!(coin::value(&usdt) == INITIAL_USDT_VALUE / 3, 0);
        assert!(object::id(pool) == recipet_pool_id, 0);
        assert!(repay_amount_x == INITIAL_USDC_VALUE / 2 + amount_to_mint_x, 0);
        assert!(repay_amount_y == INITIAL_USDT_VALUE / 3 + amount_to_mint_y, 0);

        coin::join(&mut usdc, mint<USDC>(amount_to_mint_x, ctx(test)));
        coin::join(&mut usdt, mint<USDT>(amount_to_mint_y, ctx(test)));

        dex::repay_flash_loan(
          &mut storage,
          &clock_object,
          receipt,
          usdc,
          usdt
        );

        test::return_shared(storage);
      };

      clock::destroy_for_testing(clock_object);
      test::end(scenario);
    }

  #[test]
  #[expected_failure(abort_code = dex::core::ERROR_WRONG_REPAY_AMOUNT_X)]
  fun test_flash_loan_wrong_repay_amount_x_error() {
      let scenario = scenario();
      let test = &mut scenario;

      test_create_pool_(test);
      let clock_object = clock::create_for_testing(ctx(test));
      let (_, bob) = people();
        
      next_tx(test, bob);
      {
        let storage = test::take_shared<Storage>(test);

        let (receipt, usdc, usdt) = dex::flash_loan<Stable, USDC, USDT>(&mut storage, INITIAL_USDC_VALUE / 2, INITIAL_USDT_VALUE / 3, ctx(test));

        let pool = dex::borrow_pool<Stable, USDC, USDT>(&storage);

        let (recipet_pool_id, repay_amount_x, repay_amount_y, _) = dex::get_receipt_data(&receipt);
        let (fee, precision) = dex::get_flash_loan_fee_percent();

        let amount_to_mint_x = (((INITIAL_USDC_VALUE / 2 as u256) * fee / precision) as u64);
        let amount_to_mint_y = (((INITIAL_USDT_VALUE / 3 as u256) * fee / precision) as u64);

        assert!(coin::value(&usdc) == INITIAL_USDC_VALUE / 2, 0);
        assert!(coin::value(&usdt) == INITIAL_USDT_VALUE / 3, 0);
        assert!(object::id(pool) == recipet_pool_id, 0);
        assert!(repay_amount_x == INITIAL_USDC_VALUE / 2 + amount_to_mint_x, 0);
        assert!(repay_amount_y == INITIAL_USDT_VALUE / 3 + amount_to_mint_y, 0);

        coin::join(&mut usdc, mint<USDC>(amount_to_mint_x - 1, ctx(test)));
        coin::join(&mut usdt, mint<USDT>(amount_to_mint_y, ctx(test)));

        dex::repay_flash_loan(
          &mut storage,
          &clock_object,
          receipt,
          usdc,
          usdt
        );

        test::return_shared(storage);
      };

      clock::destroy_for_testing(clock_object);
      test::end(scenario);
    }

  #[test]
  #[expected_failure(abort_code = dex::core::ERROR_WRONG_REPAY_AMOUNT_Y)]
  fun test_flash_loan_wrong_repay_amount_y_error() {
       let scenario = scenario();
      let test = &mut scenario;

      test_create_pool_(test);

      let (_, bob) = people();
      let clock_object = clock::create_for_testing(ctx(test));
      
      next_tx(test, bob);
      {
        let storage = test::take_shared<Storage>(test);

        let (receipt, usdc, usdt) = dex::flash_loan<Stable, USDC, USDT>(&mut storage, INITIAL_USDC_VALUE / 2, INITIAL_USDT_VALUE / 3, ctx(test));

        let pool = dex::borrow_pool<Stable, USDC, USDT>(&storage);

        let (recipet_pool_id, repay_amount_x, repay_amount_y, _) = dex::get_receipt_data(&receipt);
        let (fee, precision) = dex::get_flash_loan_fee_percent();

        let amount_to_mint_x = (((INITIAL_USDC_VALUE / 2 as u256) * fee / precision) as u64);
        let amount_to_mint_y = (((INITIAL_USDT_VALUE / 3 as u256) * fee / precision) as u64);

        assert!(coin::value(&usdc) == INITIAL_USDC_VALUE / 2, 0);
        assert!(coin::value(&usdt) == INITIAL_USDT_VALUE / 3, 0);
        assert!(object::id(pool) == recipet_pool_id, 0);
        assert!(repay_amount_x == INITIAL_USDC_VALUE / 2 + amount_to_mint_x, 0);
        assert!(repay_amount_y == INITIAL_USDT_VALUE / 3 + amount_to_mint_y, 0);

        coin::join(&mut usdc, mint<USDC>(amount_to_mint_x, ctx(test)));
        coin::join(&mut usdt, mint<USDT>(amount_to_mint_y - 1, ctx(test)));

        dex::repay_flash_loan(
          &mut storage,
          &clock_object,
          receipt,
          usdc,
          usdt
        );

        test::return_shared(storage);
      };

      clock::destroy_for_testing(clock_object);
      test::end(scenario);
    }

    fun remove_fee(test: &mut Scenario) {
      let (owner, _) = people();
        
       next_tx(test, owner);
       {
        let admin_cap = test::take_from_sender<DEXAdminCap>(test);
        let storage = test::take_shared<Storage>(test);

        dex::update_fee_to(&admin_cap, &mut storage, ZERO_ACCOUNT);

        test::return_shared(storage);
        test::return_to_sender(test, admin_cap)
       }
    }
}