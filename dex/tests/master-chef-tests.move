#[test_only]
module dex::master_chef_tests {

  use sui::test_scenario::{Self as test, Scenario, next_tx, ctx};
  use sui::coin::{mint_for_testing as mint,  burn_for_testing as burn};
  use sui::clock;

  use dex::master_chef::{Self, MasterChefStorage, AccountStorage, MasterChefAdmin};
  use ipx::ipx::{Self, IPXStorage, IPX, IPXAdminCap};
  use library::test_utils::{people, scenario};
  
  const START_TIMESTAMP: u64 = 0;
  const LPCOIN_ALLOCATION_POINTS: u64 = 500;

  struct LPCoin {}
  struct LPCoin2 {}

  fun test_stake_(test: &mut Scenario) {
    let (alice, _) = people();

    register_token(test);
    
    let clock_object = clock::create_for_testing(ctx(test));  
    next_tx(test, alice);
    {
      let master_chef_storage = test::take_shared<MasterChefStorage>(test);
      let account_storage = test::take_shared<AccountStorage>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);

      let coin_ipx = master_chef::stake(
        &mut master_chef_storage, 
        &mut account_storage,
        &mut ipx_storage,
        &clock_object,
        mint<LPCoin>(500, ctx(test)), 
        ctx(test)
      );

      let (_, _, _, balance) = master_chef::get_pool_info<LPCoin>(&master_chef_storage);
      let (user_balance, rewards_paid) = master_chef::get_account_info<LPCoin>(&master_chef_storage, &account_storage, alice);

      assert!(burn(coin_ipx) == 0, 0);
      assert!(balance == 500, 0);
      assert!(user_balance == 500, 0);
      assert!(rewards_paid == 0, 0);

      test::return_shared(master_chef_storage);
      test::return_shared(ipx_storage);
      test::return_shared(account_storage);
    };

    next_tx(test, alice);
    {
      let ipx_storage = test::take_shared<IPXStorage>(test);
      let account_storage = test::take_shared<AccountStorage>(test);
      let master_chef_storage = test::take_shared<MasterChefStorage>(test);

      clock::increment_for_testing(&mut clock_object, 5000);

      let coin_ipx = master_chef::stake(
        &mut master_chef_storage, 
        &mut account_storage,
        &mut ipx_storage,
        &clock_object,
        mint<LPCoin>(500, ctx(test)), 
        ctx(test)
        );

      let (_, last_reward_timestamp, accrued_ipx_per_share, balance) = master_chef::get_pool_info<LPCoin>(&master_chef_storage);
      let (user_balance, rewards_paid) = master_chef::get_account_info<LPCoin>(&master_chef_storage, &account_storage, alice);

      assert!((burn(coin_ipx) as u256) == (500 * accrued_ipx_per_share), 0);
      assert!(balance == 1000, 0);
      assert!(user_balance == 1000, 0);
      assert!(rewards_paid == 1000 * accrued_ipx_per_share, 0);
      assert!(last_reward_timestamp == 5000, 0);

      test::return_shared(master_chef_storage);
      test::return_shared(ipx_storage);
      test::return_shared(account_storage);
    };

    next_tx(test, alice);
    {
      let ipx_storage = test::take_shared<IPXStorage>(test);
      let account_storage = test::take_shared<AccountStorage>(test);
      let master_chef_storage = test::take_shared<MasterChefStorage>(test);

      clock::increment_for_testing(&mut clock_object, 12000);

      let (_, rewards_paid) = master_chef::get_account_info<LPCoin>(&master_chef_storage, &account_storage, alice);

      let pending_rewards = master_chef::get_pending_rewards<LPCoin>(&master_chef_storage, &account_storage, &clock_object, alice);

      let coin_ipx = master_chef::get_rewards<LPCoin>(
        &mut master_chef_storage, 
        &mut account_storage, 
        &mut ipx_storage,
        &clock_object,
        ctx(test)
      );

      let (_, last_reward_timestamp, accrued_ipx_per_share, balance) = master_chef::get_pool_info<LPCoin>(&master_chef_storage);
      assert!((burn(coin_ipx) as u256) == (1000 * accrued_ipx_per_share) - rewards_paid, 0);
      assert!(pending_rewards == (1000 * accrued_ipx_per_share) - rewards_paid, 0);

      let (user_balance, rewards_paid) = master_chef::get_account_info<LPCoin>(&master_chef_storage, &account_storage, alice);

      assert!(balance == 1000, 0);
      assert!(user_balance == 1000, 0);
      assert!(rewards_paid == 1000 * accrued_ipx_per_share, 0);
      assert!(last_reward_timestamp == 17000, 0);

      test::return_shared(master_chef_storage);
      test::return_shared(ipx_storage);
      test::return_shared(account_storage);   
    };

    clock::destroy_for_testing(clock_object);
  }


  #[test]
  fun test_stake() {
    let scenario = scenario();
    test_stake_(&mut scenario);
    test::end(scenario);
  }

  fun test_unstake_(test: &mut Scenario) {
    let (alice, _) = people();

    register_token(test);
    let clock_object = clock::create_for_testing(ctx(test));  

    next_tx(test, alice);
    {
      let ipx_storage = test::take_shared<IPXStorage>(test);
      let account_storage = test::take_shared<AccountStorage>(test);
      let master_chef_storage = test::take_shared<MasterChefStorage>(test);

      burn(
        master_chef::stake(
          &mut master_chef_storage, 
          &mut account_storage, 
          &mut ipx_storage,
          &clock_object,
          mint<LPCoin>(500, ctx(test)), 
          ctx(test))
       );
     
      test::return_shared(master_chef_storage);
      test::return_shared(ipx_storage);
      test::return_shared(account_storage);
    };

    next_tx(test, alice);
    {
      let ipx_storage = test::take_shared<IPXStorage>(test);
      let account_storage = test::take_shared<AccountStorage>(test);
      let master_chef_storage = test::take_shared<MasterChefStorage>(test);

      clock::increment_for_testing(&mut clock_object, 5000);

      let pending_rewards = master_chef::get_pending_rewards<LPCoin>(&master_chef_storage, &account_storage, &clock_object, alice);

      let (coin_ipx, lp_coin)= master_chef::unstake<LPCoin>(
        &mut master_chef_storage, 
        &mut account_storage, 
        &mut ipx_storage,
        &clock_object,
        300, 
        ctx(test)
      );

      let (_, last_reward_timestamp, accrued_ipx_per_share, balance) = master_chef::get_pool_info<LPCoin>(&master_chef_storage);
      let (user_balance, rewards_paid) = master_chef::get_account_info<LPCoin>(&master_chef_storage, &account_storage, alice);

      assert!(burn(lp_coin) == 300, 0);
      assert!((burn(coin_ipx) as u256) == (500 * accrued_ipx_per_share), 0);
      assert!(pending_rewards == (500 * accrued_ipx_per_share), 0);
      assert!(balance == 200, 0);
      assert!(user_balance == 200, 0);
      assert!(rewards_paid == 200 * accrued_ipx_per_share, 0);
      assert!(last_reward_timestamp == 5000, 0);
      
      test::return_shared(master_chef_storage);
      test::return_shared(ipx_storage);
      test::return_shared(account_storage);
    };

    clock::destroy_for_testing(clock_object);
  }

  #[test]
  fun test_unstake() {
    let scenario = scenario();
    test_unstake_(&mut scenario);
    test::end(scenario);
  }

  fun test_init_(test: &mut Scenario) {
    let (owner, _) = people();

    next_tx(test, owner);
    {
      master_chef::init_for_testing(ctx(test));
      ipx::init_for_testing(ctx(test));
    };

    next_tx(test, owner);
    {
      let storage = test::take_shared<MasterChefStorage>(test);

      let (ipx_per_ms, total_allocation_points, start_timestamp) = master_chef::get_master_chef_storage_info(&storage);

      let (allocation_points, last_reward_timestamp, accrued_ipx_per_share, balance) = master_chef::get_pool_info<IPX>(&storage);

      assert!(ipx_per_ms == 1268391, 0);
      assert!(total_allocation_points == 1000, 0);
      assert!(start_timestamp == 0, 0);
      assert!(allocation_points == 1000, 0);
      assert!(last_reward_timestamp == START_TIMESTAMP, 0);
      assert!(accrued_ipx_per_share == 0, 0);
      assert!(balance == 0, 0);

      test::return_shared(storage);
    };
  }

  #[test]
  fun test_init() {
    let scenario = scenario();
    test_init_(&mut scenario);
    test::end(scenario);
  }

  fun test_add_pool_(test: &mut Scenario) {
    let (alice, _) = people();

    register_token(test);

    next_tx(test, alice);
    {
      let storage = test::take_shared<MasterChefStorage>(test);

      let (lp_coin_allocation_points, last_reward_timestamp, accrued_ipx_per_share, balance) = master_chef::get_pool_info<LPCoin>(&storage);
      let (ipx_allocation_points, _, _, _) = master_chef::get_pool_info<IPX>(&storage);
      let (_, total_allocation_points, _) = master_chef::get_master_chef_storage_info(&storage);

      let ipx_allocation = LPCOIN_ALLOCATION_POINTS / 3;

      assert!(lp_coin_allocation_points == LPCOIN_ALLOCATION_POINTS, 0);
      assert!(last_reward_timestamp == START_TIMESTAMP, 0);
      assert!(accrued_ipx_per_share == 0, 0);
      assert!(balance == 0, 0);
      assert!(ipx_allocation_points == ipx_allocation, 0);
      assert!(total_allocation_points == LPCOIN_ALLOCATION_POINTS + ipx_allocation, 0);

      test::return_shared(storage);
    };
  }

  #[test]
  fun test_add_pool() {
    let scenario = scenario();
    test_add_pool_(&mut scenario);
    test::end(scenario);
  }

  fun test_update_ipx_per_ms_(test: &mut Scenario) {
    let (alice, _) = people();

    register_token(test);
    let clock_object = clock::create_for_testing(ctx(test));  

    next_tx(test, alice);
    {
      let storage = test::take_shared<MasterChefStorage>(test);
      let admin_cap = test::take_from_sender<MasterChefAdmin>(test);

      master_chef::update_ipx_per_ms(&admin_cap, &mut storage, &clock_object, 300);

      let (ipx_per_ms, _, _) = master_chef::get_master_chef_storage_info(&storage);

      assert!(ipx_per_ms == 300, 0);

      test::return_shared(storage);
      test::return_to_sender(test, admin_cap);
    };
   clock::destroy_for_testing(clock_object);
  }

  #[test]
  fun test_update_ipx_per_ms() {
    let scenario = scenario();
    test_update_ipx_per_ms_(&mut scenario);
    test::end(scenario);
  }

  fun test_set_allocation_points_(test: &mut Scenario) {
    let (owner, _) = people();

    register_token(test);
    let clock_object = clock::create_for_testing(ctx(test));  

    next_tx(test, owner);
    {
      let storage = test::take_shared<MasterChefStorage>(test);
      let admin_cap = test::take_from_sender<MasterChefAdmin>(test);
      let new_lo_coin_allocation_points = 400;

      master_chef::set_allocation_points<LPCoin>(&admin_cap, &mut storage, &clock_object, new_lo_coin_allocation_points, false);

      let (lp_coin_allocation_points, last_reward_timestamp, accrued_ipx_per_share, balance) = master_chef::get_pool_info<LPCoin>(&storage);
      let (ipx_allocation_points, _, _, _) = master_chef::get_pool_info<IPX>(&storage);
      let (_, total_allocation_points, _) = master_chef::get_master_chef_storage_info(&storage);

      let ipx_allocation = new_lo_coin_allocation_points / 3;

      assert!(lp_coin_allocation_points == new_lo_coin_allocation_points, 0);
      assert!(last_reward_timestamp == START_TIMESTAMP, 0);
      assert!(accrued_ipx_per_share == 0, 0);
      assert!(balance == 0, 0);
      assert!(ipx_allocation_points == ipx_allocation, 0);
      assert!(total_allocation_points == new_lo_coin_allocation_points + ipx_allocation, 0);

      test::return_shared(storage);
      test::return_to_sender(test, admin_cap);
    };    

    clock::destroy_for_testing(clock_object);
  }

  #[test]
  fun test_set_allocation_points() {
    let scenario = scenario();
    test_set_allocation_points_(&mut scenario);
    test::end(scenario);
  }

  fun test_update_pool_(test: &mut Scenario) {
    let (alice, _) = people();

    register_token(test);
    let clock_object = clock::create_for_testing(ctx(test));  

    let deposit_amount = 500;
    next_tx(test, alice);
    {
      let master_chef_storage = test::take_shared<MasterChefStorage>(test);
      let account_storage = test::take_shared<AccountStorage>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);

      burn(master_chef::stake<LPCoin>(
        &mut master_chef_storage, 
        &mut account_storage, 
        &mut ipx_storage, 
        &clock_object, 
        mint<LPCoin>(deposit_amount, ctx(test)),
        ctx(test))
      );

      test::return_shared(master_chef_storage);
      test::return_shared(ipx_storage);
      test::return_shared(account_storage);     
    };

    next_tx(test, alice);
    {
      let storage = test::take_shared<MasterChefStorage>(test);

      clock::increment_for_testing(&mut clock_object, 3000);

      let (pool_allocation, last_reward_timestamp, accrued_ipx_per_share, _) = master_chef::get_pool_info<LPCoin>(&storage);
      let (ipx_per_ms, total_allocation_points, _) = master_chef::get_master_chef_storage_info(&storage);

      assert!(last_reward_timestamp == START_TIMESTAMP, 0);
      assert!(accrued_ipx_per_share == 0, 0);

      master_chef::update_pool<LPCoin>(&mut storage, &clock_object);

      let (_, last_reward_timestamp_2, accrued_ipx_per_share_2, _) = master_chef::get_pool_info<LPCoin>(&storage);

      assert!(last_reward_timestamp_2 == 3000, 0);
      assert!(accrued_ipx_per_share_2 == (((pool_allocation * (3000 - last_reward_timestamp) * ipx_per_ms  / total_allocation_points) / 500) as u256), 0);

      test::return_shared(storage);
    };
    
    clock::destroy_for_testing(clock_object);
  }

  #[test]
  fun test_update_pool() {
    let scenario = scenario();
    test_update_pool_(&mut scenario);
    test::end(scenario);
  }

  fun test_update_pools_(test: &mut Scenario) {
    let (alice, _) = people();
     
     // Register first token
     register_token(test);

    let clock_object = clock::create_for_testing(ctx(test));       
     // Register second token
     next_tx(test, alice);
     {
      let storage = test::take_shared<MasterChefStorage>(test);
      let admin_cap = test::take_from_sender<MasterChefAdmin>(test);
      let account_storage = test::take_shared<AccountStorage>(test);

      master_chef::add_pool<LPCoin2>(&admin_cap, &mut storage, &mut account_storage, &clock_object, 800, false, ctx(test));

      test::return_to_sender(test, admin_cap);
      test::return_shared(account_storage);
      test::return_shared(storage);
     };

    let deposit_amount = 500;
    next_tx(test, alice);
    {
      let master_chef_storage = test::take_shared<MasterChefStorage>(test);
      let account_storage = test::take_shared<AccountStorage>(test);
      let ipx_storage = test::take_shared<IPXStorage>(test);

      clock::increment_for_testing(&mut clock_object, 1000);

      burn(
        master_chef::stake<LPCoin>(
          &mut master_chef_storage, &mut account_storage, &mut ipx_storage, &clock_object, mint<LPCoin>(deposit_amount, ctx(test)), ctx(test))
      );
      burn(
        master_chef::stake<LPCoin2>(
          &mut master_chef_storage, &mut account_storage, &mut ipx_storage, &clock_object, mint<LPCoin2>(deposit_amount * 2, ctx(test)), ctx(test))
      );

      test::return_shared(master_chef_storage);
      test::return_shared(ipx_storage);
      test::return_shared(account_storage);   
    };

    next_tx(test, alice);
    {
     let master_chef_storage = test::take_shared<MasterChefStorage>(test);
     
      clock::increment_for_testing(&mut clock_object, 2000);

      master_chef::update_all_pools(&mut master_chef_storage, &clock_object);

      let (ipx_per_ms, total_allocation_points, _) = master_chef::get_master_chef_storage_info(&master_chef_storage);
      let (lp_coin_pool_allocation, lp_coin_last_reward_timestamp, lp_coin_accrued_ipx_per_share, _) = master_chef::get_pool_info<LPCoin>(&master_chef_storage);
      let (lp_coin_2_pool_allocation, lp_coin_2_last_reward_timestamp, lp_coin_2_accrued_ipx_per_share, _) = master_chef::get_pool_info<LPCoin2>(&master_chef_storage);

      assert!(lp_coin_last_reward_timestamp == 3000, 0);
      assert!(lp_coin_2_last_reward_timestamp == 3000, 0);
      assert!(lp_coin_accrued_ipx_per_share == (((lp_coin_pool_allocation * 2000 * ipx_per_ms  / total_allocation_points) / 500) as u256), 0);
      assert!(lp_coin_2_accrued_ipx_per_share == (((lp_coin_2_pool_allocation * 2000 * ipx_per_ms  / total_allocation_points) / 1000) as u256), 0);

      test::return_shared(master_chef_storage);
    };

   clock::destroy_for_testing(clock_object); 
  }

  #[test]
  fun test_update_pools() {
    let scenario = scenario();
    test_update_pools_(&mut scenario);
    test::end(scenario);
  }

  #[test]
  #[expected_failure(abort_code = master_chef::ERROR_POOL_ADDED_ALREADY)]
  fun test_add_pool_already_added_error() {
    let scenario = scenario();
    let test = &mut scenario;
    let (owner, _) = people();

    register_token(test);

    let clock_object = clock::create_for_testing(ctx(test));  
    next_tx(test, owner);
    {
      let master_chef_storage = test::take_shared<MasterChefStorage>(test);
      let admin_cap = test::take_from_sender<MasterChefAdmin>(test);
      let account_storage = test::take_shared<AccountStorage>(test);

      master_chef::add_pool<LPCoin>(
        &admin_cap, 
        &mut master_chef_storage, 
        &mut account_storage, 
        &clock_object,
        LPCOIN_ALLOCATION_POINTS, 
        false, 
        ctx(test)
      );

      test::return_shared(master_chef_storage);
      test::return_to_sender(test, admin_cap);
      test::return_shared(account_storage);
    };

    clock::destroy_for_testing(clock_object);
    test::end(scenario);
  }

  #[test]
  #[expected_failure(abort_code = master_chef::ERROR_NO_ZERO_ALLOCATION_POINTS)]
  fun test_add_pool_zero_allocation_points_error() {
    let scenario = scenario();
    let test = &mut scenario;
    let (owner, _) = people();

    let clock_object = clock::create_for_testing(ctx(test));  

    next_tx(test, owner);
    {
      master_chef::init_for_testing(ctx(test));
      ipx::init_for_testing(ctx(test));
    };

    next_tx(test, owner);
    {
      let master_chef_storage = test::take_shared<MasterChefStorage>(test);
      let admin_cap = test::take_from_sender<MasterChefAdmin>(test);
      let account_storage = test::take_shared<AccountStorage>(test);

      master_chef::add_pool<LPCoin>(
        &admin_cap, 
        &mut master_chef_storage, 
        &mut account_storage, 
        &clock_object,
        0, 
        false, 
        ctx(test)
      );

      test::return_shared(master_chef_storage);
      test::return_to_sender(test, admin_cap);
      test::return_shared(account_storage);
    };

    clock::destroy_for_testing(clock_object);
    test::end(scenario);
  }

  #[test]
  #[expected_failure(abort_code = master_chef::ERROR_NOT_ENOUGH_BALANCE)]
  fun test_unstake_balance_error() {
    let scenario = scenario();
    let test = &mut scenario;

    let (alice, _) = people();

    register_token(test);

    let clock_object = clock::create_for_testing(ctx(test));  
    next_tx(test, alice);
    {
      let ipx_storage = test::take_shared<IPXStorage>(test);
      let account_storage = test::take_shared<AccountStorage>(test);
      let master_chef_storage = test::take_shared<MasterChefStorage>(test);

      burn(
        master_chef::stake(
          &mut master_chef_storage, 
          &mut account_storage, 
          &mut ipx_storage,
          &clock_object,
          mint<LPCoin>(500, ctx(test)), 
          ctx(test))
       );
     
      test::return_shared(master_chef_storage);
      test::return_shared(ipx_storage);
      test::return_shared(account_storage);
    };

    next_tx(test, alice);
    {
      let ipx_storage = test::take_shared<IPXStorage>(test);
      let account_storage = test::take_shared<AccountStorage>(test);
      let master_chef_storage = test::take_shared<MasterChefStorage>(test);

      clock::increment_for_testing(&mut clock_object, 5000);

      let pending_rewards = master_chef::get_pending_rewards<LPCoin>(&master_chef_storage, &account_storage, &clock_object, alice);

      let (coin_ipx, lp_coin)= master_chef::unstake<LPCoin>(
        &mut master_chef_storage, 
        &mut account_storage, 
        &mut ipx_storage,
        &clock_object,
        500 + 1, 
        ctx(test)
      );

      let (_, last_reward_timestamp, accrued_ipx_per_share, balance) = master_chef::get_pool_info<LPCoin>(&master_chef_storage);
      let (user_balance, rewards_paid) = master_chef::get_account_info<LPCoin>(&master_chef_storage, &account_storage, alice);

      assert!(burn(lp_coin) == 300, 0);
      assert!((burn(coin_ipx) as u256) == (500 * accrued_ipx_per_share), 0);
      assert!(pending_rewards == (500 * accrued_ipx_per_share), 0);
      assert!(balance == 200, 0);
      assert!(user_balance == 200, 0);
      assert!(rewards_paid == 200 * accrued_ipx_per_share, 0);
      assert!(last_reward_timestamp == 5000, 0);
      
      test::return_shared(master_chef_storage);
      test::return_shared(ipx_storage);
      test::return_shared(account_storage);
    };

    clock::destroy_for_testing(clock_object);
    test::end(scenario);
  }

  #[test]
  #[expected_failure(abort_code = master_chef::ERROR_NO_PENDING_REWARDS)]
  fun test_pending_rewards_error(){
    let scenario = scenario();
    let test = &mut scenario;

    let (alice, _) = people();

    register_token(test);

    let clock_object = clock::create_for_testing(ctx(test));  
    next_tx(test, alice);
    {
      let ipx_storage = test::take_shared<IPXStorage>(test);
      let account_storage = test::take_shared<AccountStorage>(test);
      let master_chef_storage = test::take_shared<MasterChefStorage>(test);

      burn(
        master_chef::stake(
          &mut master_chef_storage, 
          &mut account_storage, 
          &mut ipx_storage,
          &clock_object,
          mint<LPCoin>(500, ctx(test)), 
          ctx(test))
       );
     
      test::return_shared(master_chef_storage);
      test::return_shared(ipx_storage);
      test::return_shared(account_storage);
    };

    next_tx(test, alice);
    {
      let ipx_storage = test::take_shared<IPXStorage>(test);
      let account_storage = test::take_shared<AccountStorage>(test);
      let master_chef_storage = test::take_shared<MasterChefStorage>(test);

      burn(
        master_chef::get_rewards<LPCoin>(
          &mut master_chef_storage, 
          &mut account_storage, 
          &mut ipx_storage,
          &clock_object,
          ctx(test))
       );
     
      test::return_shared(master_chef_storage);
      test::return_shared(ipx_storage);
      test::return_shared(account_storage);
    };

    clock::destroy_for_testing(clock_object);
    test::end(scenario);   
  } 


  fun register_token(test: &mut Scenario) {
    let (owner, _) = people();
    let clock_object = clock::create_for_testing(ctx(test));  

    next_tx(test, owner);
    {
      master_chef::init_for_testing(ctx(test));
      ipx::init_for_testing(ctx(test));
    };

    next_tx(test, owner);
    {
      let master_chef_storage = test::take_shared<MasterChefStorage>(test);
      let admin_cap = test::take_from_sender<MasterChefAdmin>(test);
      let account_storage = test::take_shared<AccountStorage>(test);

      master_chef::add_pool<LPCoin>(
        &admin_cap, 
        &mut master_chef_storage, 
        &mut account_storage, 
        &clock_object,
        LPCOIN_ALLOCATION_POINTS, 
        false, 
        ctx(test)
      );

      test::return_shared(master_chef_storage);
      test::return_to_sender(test, admin_cap);
      test::return_shared(account_storage);
    };

    next_tx(test, owner);
    {
      let admin_cap = test::take_from_sender<IPXAdminCap>(test);   
      let ipx_storage = test::take_shared<IPXStorage>(test);  
      let master_chef_storage = test::take_shared<MasterChefStorage>(test); 

      let id = master_chef::get_publisher_id(&master_chef_storage);

      ipx::add_minter(
        &admin_cap,
        &mut ipx_storage,
        id
      );

      test::return_to_sender(test, admin_cap);
      test::return_shared(ipx_storage);
      test::return_shared(master_chef_storage);
    };

    clock::destroy_for_testing(clock_object);
  }
}