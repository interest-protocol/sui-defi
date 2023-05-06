#[test_only]
module dex::dex_volatile_tests {

    use sui::coin::{Self, mint_for_testing as mint, burn_for_testing as burn};
    use sui::test_scenario::{Self as test, Scenario, next_tx, ctx};
    use sui::test_utils::{assert_eq};
    use sui::math;
    use sui::object;
    use sui::clock;

    use dex::core::{Self as dex, DEXStorage as Storage, DEXAdminCap, LPCoin};
    use dex::curve::{Volatile};
    use library::test_utils::{people, scenario};
    use library::math::{sqrt_u256};
    use library::eth::{ETH};
    use library::usdc::{USDC};

    const INITIAL_ETHER_VALUE: u64 = 100000;
    const INITIAL_USDC_VALUE: u64 = 150000000;
    const ZERO_ACCOUNT: address = @0x0;

    struct Test {}

    fun test_create_pool_(test: &mut Scenario) {
      let (alice, _) = people();

      let lp_coin_initial_user_balance = math::sqrt(math::sqrt(INITIAL_ETHER_VALUE * INITIAL_USDC_VALUE));

      let minimum_liquidity = dex::get_minimum_liquidity();

      next_tx(test, alice);
      {
        dex::init_for_testing(ctx(test));
      };

      let clock_object = clock::create_for_testing(ctx(test));
      
      next_tx(test, alice);
      {
        let storage = test::take_shared<Storage>(test);

        let lp_coin = dex::create_v_pool(
          &mut storage,
          &clock_object,
          mint<ETH>(INITIAL_ETHER_VALUE, ctx(test)),
          mint<USDC>(INITIAL_USDC_VALUE, ctx(test)),
          ctx(test)
        );

        assert!(burn(lp_coin) == lp_coin_initial_user_balance, 0);
      
        test::return_shared(storage);
      };

      next_tx(test, alice);
      {
        let storage = test::take_shared<Storage>(test);
        let pool = dex::borrow_pool<Volatile, ETH, USDC>(&storage);
        let (ether_reserves, usdc_reserves, supply) = dex::get_amounts(pool);

        assert!(supply == lp_coin_initial_user_balance + minimum_liquidity, 0);
        assert!(ether_reserves == INITIAL_ETHER_VALUE, 0);
        assert!(usdc_reserves == INITIAL_USDC_VALUE, 0);

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

        let ether_amount = INITIAL_ETHER_VALUE / 10;

        let pool = dex::borrow_pool<Volatile, ETH, USDC>(&storage);
        let (ether_reserves, usdc_reserves, _) = dex::get_amounts(pool);

        let token_in_amount = ether_amount - ((ether_amount * 300) / 100000);
        let usdc_amount_received = (usdc_reserves * token_in_amount) / (token_in_amount + ether_reserves);

        let usdc = dex::swap_token_x<Volatile, ETH, USDC>(
          &mut storage,
          &clock_object,
          mint<ETH>(ether_amount, ctx(test)),
          0,
          ctx(test)
        );

        assert!(burn(usdc) == usdc_amount_received, 0);

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

        let usdc_amount = INITIAL_USDC_VALUE / 10;

        let pool = dex::borrow_pool<Volatile, ETH, USDC>(&storage);
        let (ether_reserves, usdc_reserves, _) = dex::get_amounts(pool);

        let token_in_amount = usdc_amount - ((usdc_amount * 300) / 100000);
        let ether_amount_received = (ether_reserves * token_in_amount) / (token_in_amount + usdc_reserves);

        let ether = dex::swap_token_y<Volatile, ETH, USDC>(
          &mut storage,
          &clock_object,
          mint<USDC>(usdc_amount, ctx(test)),
          0,
          ctx(test)
        );

        assert!(burn(ether) == ether_amount_received, 0);

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

        let ether_value = INITIAL_ETHER_VALUE / 10;
        let usdc_value = INITIAL_USDC_VALUE / 10;
        let clock_object = clock::create_for_testing(ctx(test));

        next_tx(test, bob);
        {
        let storage = test::take_shared<Storage>(test);

        let pool = dex::borrow_pool<Volatile, ETH, USDC>(&storage);
        let (_, _, supply) = dex::get_amounts(pool);

        let lp_coin = dex::add_liquidity<Volatile, ETH, USDC>(
          &mut storage,
          &clock_object,
          mint<ETH>(ether_value, ctx(test)),
          mint<USDC>(usdc_value, ctx(test)),
          0,
          ctx(test)
          );

        let pool = dex::borrow_pool<Volatile, ETH, USDC>(&storage); 
        let (ether_reserves, usdc_reserves, _) = dex::get_amounts(pool); 

        assert!(burn(lp_coin)== supply / 10, 0);
        assert!(ether_reserves == INITIAL_ETHER_VALUE + ether_value, 0);
        assert!(usdc_reserves == INITIAL_USDC_VALUE + usdc_value, 0);
        
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

        let ether_value = INITIAL_ETHER_VALUE / 10;
        let usdc_value = INITIAL_USDC_VALUE / 10;
        let clock_object = clock::create_for_testing(ctx(test));

        next_tx(test, bob);
        {
          let storage = test::take_shared<Storage>(test);

          let lp_coin = dex::add_liquidity<Volatile, ETH, USDC>(
            &mut storage,
            &clock_object,
            mint<ETH>(ether_value, ctx(test)),
            mint<USDC>(usdc_value, ctx(test)),
            0,
            ctx(test)
          );

          let pool = dex::borrow_pool<Volatile, ETH, USDC>(&storage);
          let (ether_reserves_1, usdc_reserves_1, supply_1) = dex::get_amounts(pool);

          let lp_coin_value = coin::value(&lp_coin);

          let (ether, usdc) = dex::remove_liquidity(
              &mut storage,
              &clock_object,
              lp_coin,
              0,
              0,
              ctx(test)
          );

          let pool = dex::borrow_pool<Volatile, ETH, USDC>(&storage);
          let (ether_reserves_2, usdc_reserves_2, supply_2) = dex::get_amounts(pool);

          // rounding issues
          assert_eq(burn(ether), 9969);
          assert_eq(burn(usdc), 14953805);
          assert!(supply_1 == supply_2 + lp_coin_value, 0);
          assert!(ether_reserves_1 == ether_reserves_2 + 9969, 0);
          assert!(usdc_reserves_1 == usdc_reserves_2 + 14953805, 0);

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

       let ether_value = INITIAL_ETHER_VALUE / 10;
       let usdc_value = INITIAL_USDC_VALUE / 10;

       let (_, bob) = people();
       let clock_object = clock::create_for_testing(ctx(test));

       next_tx(test, bob);
       {
        let storage = test::take_shared<Storage>(test);

        let num_swaps = 10;

        while(num_swaps > 0) {
          burn(dex::swap_token_x<Volatile, ETH, USDC>(
          &mut storage,
          &clock_object,
          mint<ETH>(INITIAL_ETHER_VALUE / 3, ctx(test)),
          0,
          ctx(test)
        ));

          burn(dex::swap_token_y<Volatile, ETH, USDC>(
          &mut storage,
          &clock_object,
          mint<USDC>(INITIAL_USDC_VALUE / 3, ctx(test)),
          0,
          ctx(test)
          ));
          num_swaps = num_swaps - 1;
        };
        
        test::return_shared(storage); 
       };

       next_tx(test, bob);
       {
        let storage = test::take_shared<Storage>(test);

        let pool = dex::borrow_pool<Volatile, ETH, USDC>(&storage);
        let (ether_reserves_1, usdc_reserves_1, supply_1) = dex::get_amounts(pool);
        let k_last = dex::get_k_last<Volatile, ETH, USDC>(&mut storage);

        let root_k = (math::sqrt_u128((ether_reserves_1 as u128) * (usdc_reserves_1 as u128)) as u256);
        let root_k_last = sqrt_u256(k_last);

        let numerator = (supply_1 as u256) * (root_k - root_k_last);
        let denominator  = (root_k * 5) + root_k_last;
        let fee = (numerator / denominator as u128);

        let lp_coin = dex::add_liquidity<Volatile, ETH, USDC>(
          &mut storage,
          &clock_object,
          mint<ETH>(ether_value, ctx(test)),
          mint<USDC>(usdc_value, ctx(test)),
          0,
          ctx(test)
        );

        let pool = dex::borrow_pool<Volatile, ETH, USDC>(&storage);
        let (_, _, supply_2) = dex::get_amounts(pool);

        assert!(fee > 0, 0);
        assert!((burn(lp_coin) as u128) + fee + (supply_1 as u128) == (supply_2 as u128), 0);
      
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

       let (_, bob) = people();
       let clock_object = clock::create_for_testing(ctx(test));

       next_tx(test, bob);
        {
        let storage = test::take_shared<Storage>(test);

        let num_swaps = 10;

        while(num_swaps > 0) {
          burn(dex::swap_token_x<Volatile, ETH, USDC>(
          &mut storage,
          &clock_object,
          mint<ETH>(INITIAL_ETHER_VALUE / 3, ctx(test)),
          0,
          ctx(test)
        ));

          burn(dex::swap_token_y<Volatile, ETH, USDC>(
          &mut storage,
          &clock_object,
          mint<USDC>(INITIAL_USDC_VALUE / 3, ctx(test)),
          0,
          ctx(test)
          ));
          num_swaps = num_swaps - 1;
        };

        test::return_shared(storage); 
       };

       next_tx(test, bob);
       {
        let storage = test::take_shared<Storage>(test);

        let pool = dex::borrow_pool<Volatile, ETH, USDC>(&storage);
        let (ether_reserves_1, usdc_reserves_1, supply_1) = dex::get_amounts(pool);
        let k_last = dex::get_k_last<Volatile, ETH, USDC>(&mut storage);

        let root_k = (math::sqrt_u128((ether_reserves_1 as u128) * (usdc_reserves_1 as u128)) as u256);
        let root_k_last = sqrt_u256(k_last);

        let numerator = (supply_1 as u256) * (root_k - root_k_last);
        let denominator  = (root_k * 5) + root_k_last;
        let fee = numerator / denominator;

        let withdraw_amount = supply_1 / 3;

        let (ether, usdc) = dex::remove_liquidity<Volatile, ETH, USDC>(
          &mut storage,
          &clock_object,
          mint<LPCoin<Volatile, ETH, USDC>>(withdraw_amount, ctx(test)),
          0,
          0,
          ctx(test)
        );

        burn(ether);
        burn(usdc);

        let pool = dex::borrow_pool<Volatile, ETH, USDC>(&storage);
        let (_, _, supply_2) = dex::get_amounts(pool);

        assert_eq(fee > 0, true);
        assert_eq((supply_2 as u256), (supply_1 as u256) + fee - (withdraw_amount as u256));

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

        let (receipt, ether, usdc) = dex::flash_loan<Volatile, ETH, USDC>(&mut storage, INITIAL_ETHER_VALUE / 2, INITIAL_USDC_VALUE / 3, ctx(test));

        let pool = dex::borrow_pool<Volatile, ETH, USDC>(&storage);

        let (recipet_pool_id, repay_amount_x, repay_amount_y, _) = dex::get_receipt_data(&receipt);
        let (fee, precision) = dex::get_flash_loan_fee_percent();

        let amount_to_mint_x = (((INITIAL_ETHER_VALUE / 2 as u256) * fee / precision) as u64);
        let amount_to_mint_y = (((INITIAL_USDC_VALUE / 3 as u256) * fee / precision) as u64);

        assert!(coin::value(&ether) == INITIAL_ETHER_VALUE / 2, 0);
        assert!(coin::value(&usdc) == INITIAL_USDC_VALUE / 3, 0);
        assert!(object::id(pool) == recipet_pool_id, 0);
        assert!(repay_amount_x == INITIAL_ETHER_VALUE / 2 + amount_to_mint_x, 0);
        assert!(repay_amount_y == INITIAL_USDC_VALUE / 3 + amount_to_mint_y, 0);
        assert!(dex::is_pool_locked<Volatile, ETH, USDC>(&storage), 0);

        coin::join(&mut ether, mint<ETH>(amount_to_mint_x, ctx(test)));
        coin::join(&mut usdc, mint<USDC>(amount_to_mint_y, ctx(test)));

        dex::repay_flash_loan<Volatile, ETH, USDC>(
          &mut storage,
          &clock_object,
          receipt,
          ether,
          usdc
        );

        assert!(!dex::is_pool_locked<Volatile, ETH, USDC>(&storage), 0);

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
  fun test_create_pool_zero_value_x_error() {
      let scenario = scenario();
      let (alice, _) = people();
      let test = &mut scenario;

      next_tx(test, alice);
      {
       dex::init_for_testing(ctx(test));
      };

      let clock_object = clock::create_for_testing(ctx(test));
      next_tx(test, alice);
      {
        let storage = test::take_shared<Storage>(test);

        burn(dex::create_v_pool(
          &mut storage,
          &clock_object,
          mint<ETH>(0, ctx(test)),
          mint<USDC>(INITIAL_USDC_VALUE, ctx(test)),
          ctx(test)
        ));

        test::return_shared(storage);
      };

      clock::destroy_for_testing(clock_object);      
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
      };

      next_tx(test, alice);
      {
        let storage = test::take_shared<Storage>(test);

        burn(dex::create_v_pool(
          &mut storage,
          &clock_object,
          mint<ETH>(INITIAL_ETHER_VALUE, ctx(test)),
          mint<USDC>(0, ctx(test)),
          ctx(test)
        ));

        test::return_shared(storage);
      };

      clock::destroy_for_testing(clock_object);
      test::end(scenario);
  }

  #[test]
  #[expected_failure(abort_code = dex::core::ERROR_UNSORTED_COINS)]
  fun test_create_pool_unsorted_coins_error() {
      let scenario = scenario();
      let (alice, _) = people();
      let test = &mut scenario;

      next_tx(test, alice);
      {
       dex::init_for_testing(ctx(test));
      };

      let clock_object = clock::create_for_testing(ctx(test));

      next_tx(test, alice);
      {
        let storage = test::take_shared<Storage>(test);

        burn(dex::create_v_pool(
          &mut storage,
          &clock_object,
          mint<USDC>(INITIAL_USDC_VALUE, ctx(test)),
          mint<ETH>(INITIAL_ETHER_VALUE, ctx(test)),
          ctx(test)
        ));

        test::return_shared(storage);
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

      test_create_pool_(test);
      
      let ether_value = 0;
      let usdc_value = INITIAL_USDC_VALUE / 10;
      let clock_object = clock::create_for_testing(ctx(test));

      next_tx(test, alice);
      {
        let storage = test::take_shared<Storage>(test);

        burn(dex::add_liquidity<Volatile, ETH, USDC>(
          &mut storage,
          &clock_object,
          mint<ETH>(ether_value, ctx(test)),
          mint<USDC>(usdc_value, ctx(test)),
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
      
      let ether_value = INITIAL_ETHER_VALUE / 10;
      let usdc_value = 0;
      let clock_object = clock::create_for_testing(ctx(test));

      next_tx(test, alice);
      {
        let storage = test::take_shared<Storage>(test);

        burn(dex::add_liquidity<Volatile, ETH, USDC>(
          &mut storage,
          &clock_object,
          mint<ETH>(ether_value, ctx(test)),
          mint<USDC>(usdc_value, ctx(test)),
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

        let (usdc, usdt) = dex::remove_liquidity<Volatile, ETH, USDC>(
          &mut storage,
          &clock_object,
          mint<LPCoin<Volatile, ETH, USDC>>(0, ctx(test)),
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
      
      let ether_value = INITIAL_ETHER_VALUE / 10;
      let usdc_value = INITIAL_USDC_VALUE / 10;
      let clock_object = clock::create_for_testing(ctx(test));

       next_tx(test, alice);
        {
          let storage = test::take_shared<Storage>(test);

          let lp_coin = dex::add_liquidity<Volatile, ETH, USDC>(
            &mut storage,
            &clock_object,
            mint<ETH>(ether_value, ctx(test)),
            mint<USDC>(usdc_value, ctx(test)),
            0,
            ctx(test)
          );

          let (ether, usdc) = dex::remove_liquidity(
              &mut storage,
              &clock_object,             
              lp_coin,
              ether_value,
              0,
              ctx(test)
          );

          burn(usdc);
          burn(ether);
        
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
      
      let ether_value = INITIAL_ETHER_VALUE / 10;
      let usdc_value = INITIAL_USDC_VALUE / 10;
      let clock_object = clock::create_for_testing(ctx(test));

       next_tx(test, alice);
        {
          let storage = test::take_shared<Storage>(test);

          let lp_coin = dex::add_liquidity<Volatile, ETH, USDC>(
            &mut storage,
            &clock_object,
            mint<ETH>(ether_value, ctx(test)),
            mint<USDC>(usdc_value, ctx(test)),
            0,
            ctx(test)
          );

          let (ether, usdc) = dex::remove_liquidity(
              &mut storage,
              &clock_object,
              lp_coin,
              0,
              usdc_value,
              ctx(test)
          );

          burn(usdc);
          burn(ether);
        
          test::return_shared(storage);
        };

      clock::destroy_for_testing(clock_object);  
      test::end(scenario);
  }

  #[test]
  #[expected_failure(abort_code = dex::core::ERROR_ZERO_VALUE_SWAP)]
  fun test_swap_token_x_zero_value_error() {
    let scenario = scenario();
    let test = &mut scenario;
    
    test_create_pool_(test);

    let (_, bob) = people();
    let clock_object = clock::create_for_testing(ctx(test));

    next_tx(test, bob);
    {
      let storage = test::take_shared<Storage>(test);

      let ether_amount = INITIAL_ETHER_VALUE / 10;

      let pool = dex::borrow_pool<Volatile, ETH, USDC>(&storage);
      let (ether_reserves, usdc_reserves, _) = dex::get_amounts(pool);

      let token_in_amount = ether_amount - ((ether_amount * 300) / 100000);
      let usdc_amount_received = (usdc_reserves * token_in_amount) / (token_in_amount + ether_reserves);

      let usdc = dex::swap_token_x<Volatile, ETH, USDC>(
          &mut storage,
          &clock_object,
          mint<ETH>(0, ctx(test)),
          0,
          ctx(test)
        );

      assert!(burn(usdc) == usdc_amount_received, 0);
      
      test::return_shared(storage);
    };

     clock::destroy_for_testing(clock_object);
     test::end(scenario);
  }

  #[test]
  #[expected_failure(abort_code = dex::core::ERROR_SLIPPAGE)]
  fun test_swap_token_x_slippage_error() {
    let scenario = scenario();
    let test = &mut scenario;
    
    test_create_pool_(test);
    let clock_object = clock::create_for_testing(ctx(test));

    let (_, bob) = people();

    next_tx(test, bob);
    {
      let storage = test::take_shared<Storage>(test);

      let ether_amount = INITIAL_ETHER_VALUE / 10;

      let pool = dex::borrow_pool<Volatile, ETH, USDC>(&storage);
      let (ether_reserves, usdc_reserves, _) = dex::get_amounts(pool);

      let token_in_amount = ether_amount - ((ether_amount * 300) / 100000);
      let usdc_amount_received = (usdc_reserves * token_in_amount) / (token_in_amount + ether_reserves);

      let usdc = dex::swap_token_x<Volatile, ETH, USDC>(
          &mut storage,
          &clock_object,
          mint<ETH>(token_in_amount, ctx(test)),
          usdc_amount_received + 1,
          ctx(test)
        );

      assert!(burn(usdc) == usdc_amount_received, 0);

      test::return_shared(storage);
    };

     clock::destroy_for_testing(clock_object); 
     test::end(scenario);
  }

  #[test]
  #[expected_failure(abort_code = dex::core::ERROR_ZERO_VALUE_SWAP)]
  fun test_swap_token_y_zero_value_error() {
    let scenario = scenario();
    let test = &mut scenario;
    
    test_create_pool_(test);

    let (_, bob) = people();
    let clock_object = clock::create_for_testing(ctx(test));

    next_tx(test, bob);
    {
      let storage = test::take_shared<Storage>(test);

      let usdc_amount = INITIAL_USDC_VALUE / 10;

      let pool = dex::borrow_pool<Volatile, ETH, USDC>(&storage);
      let (ether_reserves, usdc_reserves, _) = dex::get_amounts(pool);

      let token_in_amount = usdc_amount - ((usdc_amount * 300) / 100000);
      let ether_amount_received = (ether_reserves * token_in_amount) / (token_in_amount + usdc_reserves);

      let ether = dex::swap_token_y<Volatile, ETH, USDC>(
          &mut storage,
          &clock_object,
          mint<USDC>(0, ctx(test)),
          0,
          ctx(test)
        );

        assert!(burn(ether) == ether_amount_received, 0);

        test::return_shared(storage);
       };

     clock::destroy_for_testing(clock_object);  
     test::end(scenario);
  }

  #[test]
  #[expected_failure(abort_code = dex::core::ERROR_SLIPPAGE)]
  fun test_swap_token_y_slippage_error() {
    let scenario = scenario();
    let test = &mut scenario;
    
    test_create_pool_(test);

    let (_, bob) = people();
    let clock_object = clock::create_for_testing(ctx(test));

    next_tx(test, bob);
    {
      let storage = test::take_shared<Storage>(test);

      let usdc_amount = INITIAL_USDC_VALUE / 10;

      let pool = dex::borrow_pool<Volatile, ETH, USDC>(&storage);
      let (ether_reserves, usdc_reserves, _) = dex::get_amounts(pool);

      let token_in_amount = usdc_amount - ((usdc_amount * 300) / 100000);
      let ether_amount_received = (ether_reserves * token_in_amount) / (token_in_amount + usdc_reserves);

      let ether = dex::swap_token_y<Volatile, ETH, USDC>(
          &mut storage,
          &clock_object,
          mint<USDC>(token_in_amount, ctx(test)),
          ether_amount_received + 1,
          ctx(test)
        );

        assert!(burn(ether) == ether_amount_received, 0);

        test::return_shared(storage);
       };

     clock::destroy_for_testing(clock_object);
     test::end(scenario);
  }

  #[test]
  #[expected_failure(abort_code = dex::core::ERROR_NOT_ENOUGH_LIQUIDITY_TO_LEND)]
  fun test_flash_loan_not_enough_liquidity_to_lend() {
    let scenario = scenario();
    let test = &mut scenario;
    test_create_pool_(test);

    let (_, bob) = people();

    let clock_object = clock::create_for_testing(ctx(test));    
    
    next_tx(test, bob);
    {
      let storage = test::take_shared<Storage>(test);

      let (receipt, ether, usdc) = dex::flash_loan<Volatile, ETH, USDC>(&mut storage, INITIAL_ETHER_VALUE + 1, INITIAL_USDC_VALUE / 3, ctx(test));

      let pool = dex::borrow_pool<Volatile, ETH, USDC>(&storage);

      let (recipet_pool_id, repay_amount_x, repay_amount_y, _) = dex::get_receipt_data(&receipt);
      let (fee, precision) = dex::get_flash_loan_fee_percent();

      let amount_to_mint_x = (((INITIAL_ETHER_VALUE / 2 as u256) * fee / precision) as u64);
      let amount_to_mint_y = (((INITIAL_USDC_VALUE / 3 as u256) * fee / precision) as u64);

      assert!(coin::value(&ether) == INITIAL_ETHER_VALUE / 2, 0);
      assert!(coin::value(&usdc) == INITIAL_USDC_VALUE / 3, 0);
      assert!(object::id(pool) == recipet_pool_id, 0);
      assert!(repay_amount_x == INITIAL_ETHER_VALUE / 2 + amount_to_mint_x, 0);
      assert!(repay_amount_y == INITIAL_USDC_VALUE / 3 + amount_to_mint_y, 0);

      coin::join(&mut ether, mint<ETH>(amount_to_mint_x, ctx(test)));
      coin::join(&mut usdc, mint<USDC>(amount_to_mint_y, ctx(test)));

      dex::repay_flash_loan<Volatile, ETH, USDC>(
          &mut storage,
          &clock_object,
          receipt,
          ether,
          usdc
        );

      test::return_shared(clock_object);
      test::return_shared(storage);
    };
    test::end(scenario);
  }

  #[test]
  #[expected_failure(abort_code = dex::core::ERROR_WRONG_REPAY_AMOUNT_X)]
  fun test_flash_loan_wrong_repay_amount_x_error() {
    let scenario = scenario();
    let test = &mut scenario;
    test_create_pool_(test);

    let (_, bob) = people();
    let clock_object = clock::create_for_testing(ctx(test));

    next_tx(test, bob);
    {
      let storage = test::take_shared<Storage>(test);

      let (receipt, ether, usdc) = dex::flash_loan<Volatile, ETH, USDC>(&mut storage, INITIAL_ETHER_VALUE / 2, INITIAL_USDC_VALUE / 3, ctx(test));

      let pool = dex::borrow_pool<Volatile, ETH, USDC>(&storage);

      let (recipet_pool_id, repay_amount_x, repay_amount_y, _) = dex::get_receipt_data(&receipt);
      let (fee, precision) = dex::get_flash_loan_fee_percent();

      let amount_to_mint_x = (((INITIAL_ETHER_VALUE / 2 as u256) * fee / precision) as u64);
      let amount_to_mint_y = (((INITIAL_USDC_VALUE / 3 as u256) * fee / precision) as u64);

      assert!(coin::value(&ether) == INITIAL_ETHER_VALUE / 2, 0);
      assert!(coin::value(&usdc) == INITIAL_USDC_VALUE / 3, 0);
      assert!(object::id(pool) == recipet_pool_id, 0);
      assert!(repay_amount_x == INITIAL_ETHER_VALUE / 2 + amount_to_mint_x, 0);
      assert!(repay_amount_y == INITIAL_USDC_VALUE / 3 + amount_to_mint_y, 0);

      coin::join(&mut ether, mint<ETH>(amount_to_mint_x - 1, ctx(test)));
      coin::join(&mut usdc, mint<USDC>(amount_to_mint_y, ctx(test)));

      dex::repay_flash_loan<Volatile, ETH, USDC>(
          &mut storage,
          &clock_object,
          receipt,
          ether,
          usdc
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
      
      let (receipt, ether, usdc) = dex::flash_loan<Volatile, ETH, USDC>(&mut storage, INITIAL_ETHER_VALUE / 2, INITIAL_USDC_VALUE / 3, ctx(test));

      let pool = dex::borrow_pool<Volatile, ETH, USDC>(&storage);

      let (recipet_pool_id, repay_amount_x, repay_amount_y, _) = dex::get_receipt_data(&receipt);
      let (fee, precision) = dex::get_flash_loan_fee_percent();

      let amount_to_mint_x = (((INITIAL_ETHER_VALUE / 2 as u256) * fee / precision) as u64);
      let amount_to_mint_y = (((INITIAL_USDC_VALUE / 3 as u256) * fee / precision) as u64);

      assert!(coin::value(&ether) == INITIAL_ETHER_VALUE / 2, 0);
      assert!(coin::value(&usdc) == INITIAL_USDC_VALUE / 3, 0);
      assert!(object::id(pool) == recipet_pool_id, 0);
      assert!(repay_amount_x == INITIAL_ETHER_VALUE / 2 + amount_to_mint_x, 0);
      assert!(repay_amount_y == INITIAL_USDC_VALUE / 3 + amount_to_mint_y, 0);

      coin::join(&mut ether, mint<ETH>(amount_to_mint_x, ctx(test)));
      coin::join(&mut usdc, mint<USDC>(amount_to_mint_y - 1, ctx(test)));

      dex::repay_flash_loan<Volatile, ETH, USDC>(
          &mut storage,
          &clock_object,
          receipt,
          ether,
          usdc
        );

      test::return_shared(storage);
    };

    clock::destroy_for_testing(clock_object);
    test::end(scenario);
  }


  #[test]
  #[expected_failure(abort_code = dex::core::ERROR_POOL_IS_LOCKED)]
  fun test_flash_loan_add_liquidity_error() {
    let scenario = scenario();
    let test = &mut scenario;
    test_create_pool_(test);

    let (_, bob) = people();
    let clock_object = clock::create_for_testing(ctx(test));

    next_tx(test, bob);
    {
      let storage = test::take_shared<Storage>(test);
      
      let (receipt, ether, usdc) = dex::flash_loan<Volatile, ETH, USDC>(&mut storage, INITIAL_ETHER_VALUE / 2, INITIAL_USDC_VALUE / 3, ctx(test));

      burn(dex::add_liquidity<Volatile, ETH, USDC>(
        &mut storage,
        &clock_object,
        mint<ETH>(1, ctx(test)),
        mint<USDC>(1, ctx(test)),
        0,
        ctx(test)
      ));

      dex::repay_flash_loan<Volatile, ETH, USDC>(
          &mut storage,
          &clock_object,
          receipt,
          ether,
          usdc
        );

      test::return_shared(storage);
    };

    clock::destroy_for_testing(clock_object);
    test::end(scenario);
  }

  #[test]
  #[expected_failure(abort_code = dex::core::ERROR_POOL_IS_LOCKED)]
  fun test_flash_loan_remove_liquidity_error() {
    let scenario = scenario();
    let test = &mut scenario;
    test_create_pool_(test);

    let (_, bob) = people();
    let clock_object = clock::create_for_testing(ctx(test));

    next_tx(test, bob);
    {
      let storage = test::take_shared<Storage>(test);
      
      let (receipt, ether, usdc) = dex::flash_loan<Volatile, ETH, USDC>(&mut storage, INITIAL_ETHER_VALUE / 2, INITIAL_USDC_VALUE / 3, ctx(test));

      let (x, y) = dex::remove_liquidity<Volatile, ETH, USDC>(
        &mut storage,
        &clock_object,
        mint<LPCoin<Volatile, ETH, USDC>>(1, ctx(test)),
        0,
        0,
        ctx(test)
      );

      burn(x);
      burn(y);

      dex::repay_flash_loan<Volatile, ETH, USDC>(
          &mut storage,
          &clock_object,
          receipt,
          ether,
          usdc
        );

      test::return_shared(storage);
    };

    clock::destroy_for_testing(clock_object);
    test::end(scenario);
  }

  #[test]
  #[expected_failure(abort_code = dex::core::ERROR_POOL_IS_LOCKED)]
  fun test_flash_loan_swap_token_x_error() {
    let scenario = scenario();
    let test = &mut scenario;
    test_create_pool_(test);

    let (_, bob) = people();
    let clock_object = clock::create_for_testing(ctx(test));

    next_tx(test, bob);
    {
      let storage = test::take_shared<Storage>(test);
      
      let (receipt, ether, usdc) = dex::flash_loan<Volatile, ETH, USDC>(&mut storage, INITIAL_ETHER_VALUE / 2, INITIAL_USDC_VALUE / 3, ctx(test));

      burn(dex::swap_token_x<Volatile, ETH, USDC>(
        &mut storage,
        &clock_object,
        mint<ETH>(1, ctx(test)),
        0,
        ctx(test)
      ));

      dex::repay_flash_loan<Volatile, ETH, USDC>(
          &mut storage,
          &clock_object,
          receipt,
          ether,
          usdc
        );

      test::return_shared(storage);
    };

    clock::destroy_for_testing(clock_object);
    test::end(scenario);
  }

  #[test]
  #[expected_failure(abort_code = dex::core::ERROR_POOL_IS_LOCKED)]
  fun test_flash_loan_swap_token_y_error() {
    let scenario = scenario();
    let test = &mut scenario;
    test_create_pool_(test);

    let (_, bob) = people();
    let clock_object = clock::create_for_testing(ctx(test));

    next_tx(test, bob);
    {
      let storage = test::take_shared<Storage>(test);
      
      let (receipt, ether, usdc) = dex::flash_loan<Volatile, ETH, USDC>(&mut storage, INITIAL_ETHER_VALUE / 2, INITIAL_USDC_VALUE / 3, ctx(test));

      burn(dex::swap_token_y<Volatile, ETH, USDC>(
        &mut storage,
        &clock_object,
        mint<USDC>(1, ctx(test)),
        0,
        ctx(test)
      ));

      dex::repay_flash_loan<Volatile, ETH, USDC>(
          &mut storage,
          &clock_object,
          receipt,
          ether,
          usdc
        );

      test::return_shared(storage);
    };

    clock::destroy_for_testing(clock_object);
    test::end(scenario);
  }

  #[test]
  #[expected_failure(abort_code = dex::core::ERROR_POOL_IS_LOCKED)]
  fun test_two_flash_loan_error() {
    let scenario = scenario();
    let test = &mut scenario;
    test_create_pool_(test);

    let (_, bob) = people();
    let clock_object = clock::create_for_testing(ctx(test));

    next_tx(test, bob);
    {
      let storage = test::take_shared<Storage>(test);
      
      let (receipt, ether, usdc) = dex::flash_loan<Volatile, ETH, USDC>(&mut storage, INITIAL_ETHER_VALUE / 2, INITIAL_USDC_VALUE / 3, ctx(test));

      let (receipt_2, ether_2, usdc_2) = dex::flash_loan<Volatile, ETH, USDC>(&mut storage, INITIAL_ETHER_VALUE / 2, INITIAL_USDC_VALUE / 3, ctx(test));

      dex::repay_flash_loan<Volatile, ETH, USDC>(
          &mut storage,
          &clock_object,
          receipt,
          ether,
          usdc
        );

      dex::repay_flash_loan<Volatile, ETH, USDC>(
          &mut storage,
          &clock_object,
          receipt_2,
          ether_2,
          usdc_2
        );


      test::return_shared(storage);
    };

    clock::destroy_for_testing(clock_object);
    test::end(scenario);
  }

  #[test]
  #[expected_failure(abort_code = dex::core::ERROR_WRONG_CURVE)]
  fun test_add_liquidity_curve_error() {
    let scenario = scenario();

    let test = &mut scenario;
    test_create_pool_(test);

    let (alice, _) = people();
    let clock_object = clock::create_for_testing(ctx(test));

    next_tx(test, alice);
    {
      let storage = test::take_shared<Storage>(test);

        burn(dex::add_liquidity<Test, ETH, USDC>(
          &mut storage,
          &clock_object,
          mint<ETH>(1, ctx(test)),
          mint<USDC>(1, ctx(test)),
          0,
          ctx(test)
        ));
  
        test::return_shared(storage);
    };
  
    clock::destroy_for_testing(clock_object);
    test::end(scenario);  
  }

  #[test]
  #[expected_failure(abort_code = dex::core::ERROR_WRONG_CURVE)]
  fun test_remove_liquidity_curve_error() {
    let scenario = scenario();

    let test = &mut scenario;
    test_create_pool_(test);

    let (alice, _) = people();

    let clock_object = clock::create_for_testing(ctx(test));

    next_tx(test, alice);
    {
      let storage = test::take_shared<Storage>(test);

      let (ether, usdc) = dex::remove_liquidity<Test, ETH, USDC>(
              &mut storage,
              &clock_object,
              mint<LPCoin<Test, ETH, USDC>>(1, ctx(test)),
              0,
              0,
              ctx(test)
      );

      burn(ether);
      burn(usdc);
   
      test::return_shared(storage);
    };

    clock::destroy_for_testing(clock_object);
    test::end(scenario);  
  }


  #[test]
  #[expected_failure(abort_code = dex::core::ERROR_WRONG_CURVE)]
  fun test_swap_token_x_curve_error() {
    let scenario = scenario();

    let test = &mut scenario;
    test_create_pool_(test);

    let (alice, _) = people();
    let clock_object = clock::create_for_testing(ctx(test));

    next_tx(test, alice);
    {
      let storage = test::take_shared<Storage>(test);

      burn(dex::swap_token_x<Test, ETH, USDC>(
          &mut storage,
          &clock_object,
          mint<ETH>(1, ctx(test)),
          0,
          ctx(test)
      ));

      test::return_shared(storage);
    };

    clock::destroy_for_testing(clock_object);
    test::end(scenario);  
  }

  #[test]
  #[expected_failure(abort_code = dex::core::ERROR_WRONG_CURVE)]
  fun test_swap_token_y_curve_error() {
    let scenario = scenario();

    let test = &mut scenario;
    test_create_pool_(test);

    let (alice, _) = people();
    let clock_object = clock::create_for_testing(ctx(test));

    next_tx(test, alice);
    {
      let storage = test::take_shared<Storage>(test);

      burn(dex::swap_token_y<Test, ETH, USDC>(
          &mut storage,
          &clock_object,
          mint<USDC>(1, ctx(test)),
          0,
          ctx(test)
      ));

      test::return_shared(storage);
    };

    clock::destroy_for_testing(clock_object);
    test::end(scenario);  
  }
  
  #[test]
  #[expected_failure(abort_code = dex::core::ERROR_WRONG_CURVE)]
  fun test_flash_loan_curve_error() {
    let scenario = scenario();

    let test = &mut scenario;
    test_create_pool_(test);

    let (alice, _) = people();
    let clock_object = clock::create_for_testing(ctx(test));

    next_tx(test, alice);
    {
      let storage = test::take_shared<Storage>(test);

      let (receipt, ether, usdc) = dex::flash_loan<Test, ETH, USDC>(&mut storage, INITIAL_ETHER_VALUE / 2, INITIAL_USDC_VALUE / 3, ctx(test));
       
      dex::repay_flash_loan<Test, ETH, USDC>(
          &mut storage,
          &clock_object,
          receipt,
          ether,
          usdc
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