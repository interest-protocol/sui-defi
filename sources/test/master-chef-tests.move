#[test_only]
module interest_protocol::ipx_tests {

  use sui::test_scenario::{Self as test, Scenario, next_tx, ctx};
  use sui::coin::{mint_for_testing as mint};
  // use sui::tx_context;
  use sui::clock::{Self, Clock};

  use interest_protocol::master_chef::{Self, MasterChefStorage, AccountStorage, MasterChefAdmin};
  use interest_protocol::ipx::{Self, IPXStorage};
  use interest_protocol::test_utils::{people, scenario, burn};
  
  const START_EPOCH: u64 = 4;
  const LPCOIN_ALLOCATION_POINTS: u64 = 500;

  struct LPCoin {}
  struct LPCoin2 {}

  fun test_stake_(test: &mut Scenario) {
    let (alice, _) = people();

    register_token(test);

    next_tx(test, alice);
    {
      let master_chef_storage = test::take_shared<MasterChefStorage>(test);
      let account_storage = test::take_shared<AccountStorage>(test);
      let clock_object = test::take_shared<Clock>(test);
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
      test::return_shared(clock_object);
      test::return_shared(ipx_storage);
      test::return_shared(account_storage);
    };

    next_tx(test, alice);
    {
      let ipx_storage = test::take_shared<IPXStorage>(test);
      let account_storage = test::take_shared<AccountStorage>(test);
      let clock_object = test::take_shared<Clock>(test);
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
      test::return_shared(clock_object);
      test::return_shared(ipx_storage);
      test::return_shared(account_storage);
    };

    next_tx(test, alice);
    {
      let ipx_storage = test::take_shared<IPXStorage>(test);
      let account_storage = test::take_shared<AccountStorage>(test);
      let clock_object = test::take_shared<Clock>(test);
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
      test::return_shared(clock_object);
      test::return_shared(ipx_storage);
      test::return_shared(account_storage);   
    };
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

    next_tx(test, alice);
    {
      let ipx_storage = test::take_shared<IPXStorage>(test);
      let account_storage = test::take_shared<AccountStorage>(test);
      let clock_object = test::take_shared<Clock>(test);
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
      test::return_shared(clock_object);
      test::return_shared(ipx_storage);
      test::return_shared(account_storage);
    };

    next_tx(test, alice);
    {
      let ipx_storage = test::take_shared<IPXStorage>(test);
      let account_storage = test::take_shared<AccountStorage>(test);
      let clock_object = test::take_shared<Clock>(test);
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
      test::return_shared(clock_object);
      test::return_shared(ipx_storage);
      test::return_shared(account_storage);
    };
  }

  #[test]
  fun test_unstake() {
    let scenario = scenario();
    test_unstake_(&mut scenario);
    test::end(scenario);
  }

  // fun test_init_(test: &mut Scenario) {
  //   let (owner, _) = people();

  //   next_tx(test, owner);
  //   {
  //     ipx::init_for_testing(ctx(test));
  //   };

  //   next_tx(test, owner);
  //   {
  //     let metadata = test::take_immutable<CoinMetadata<IPX>>(test);
  //     let ipx_storage = test::take_shared<IPXStorage>(test);

  //     let decimals = coin::get_decimals<IPX>(&metadata);

  //     let (supply, ipx_per_epoch, total_allocation_points, start_epoch) = ipx::get_ipx_storage_info(&ipx_storage);

  //     let (allocation_points, last_reward_epoch, accrued_ipx_per_share, balance) = ipx::get_pool_info<IPX>(&ipx_storage);

  //     assert!(decimals == 9, 0);
  //     assert!(supply == ipx::get_ipx_pre_mint_amount(), 0);
  //     assert!(ipx_per_epoch == 100000000000, 0);
  //     assert!(total_allocation_points == 1000, 0);
  //     assert!(start_epoch == 4, 0);
  //     assert!(allocation_points == 1000, 0);
  //     assert!(last_reward_epoch == START_EPOCH, 0);
  //     assert!(accrued_ipx_per_share == 0, 0);
  //     assert!(balance == 0, 0);

  //     test::return_immutable(metadata);
  //     test::return_shared(ipx_storage);
  //   };
  // }

  // #[test]
  // fun test_init() {
  //   let scenario = scenario();
  //   test_init_(&mut scenario);
  //   test::end(scenario);
  // }

  // fun test_add_pool_(test: &mut Scenario) {
  //   let (alice, _) = people();

  //   register_token(test);

  //   next_tx(test, alice);
  //   {
  //     let ipx_storage = test::take_shared<IPXStorage>(test);

  //     let (lp_coin_allocation_points, last_reward_epoch, accrued_ipx_per_share, balance) = ipx::get_pool_info<LPCoin>(&ipx_storage);
  //     let (ipx_allocation_points, _, _, _) = ipx::get_pool_info<IPX>(&ipx_storage);
  //     let (_, _, total_allocation_points, _) = ipx::get_ipx_storage_info(&ipx_storage);

  //     let ipx_allocation = LPCOIN_ALLOCATION_POINTS / 3;

  //     assert!(lp_coin_allocation_points == LPCOIN_ALLOCATION_POINTS, 0);
  //     assert!(last_reward_epoch == START_EPOCH, 0);
  //     assert!(accrued_ipx_per_share == 0, 0);
  //     assert!(balance == 0, 0);
  //     assert!(ipx_allocation_points == ipx_allocation, 0);
  //     assert!(total_allocation_points == LPCOIN_ALLOCATION_POINTS + ipx_allocation, 0);

  //     test::return_shared(ipx_storage);
  //   };
  // }

  // #[test]
  // fun test_add_pool() {
  //   let scenario = scenario();
  //   test_add_pool_(&mut scenario);
  //   test::end(scenario);
  // }

  // fun test_update_ipx_per_epoch_(test: &mut Scenario) {
  //   let (alice, _) = people();

  //   register_token(test);

  //   next_tx(test, alice);
  //   {
  //     let ipx_storage = test::take_shared<IPXStorage>(test);
  //     let admin_cap = test::take_from_sender<IPXAdmin>(test);

  //     ipx::update_ipx_per_epoch(&admin_cap, &mut ipx_storage, 300, ctx(test));

  //     let (_, ipx_per_epoch, _, _) = ipx::get_ipx_storage_info(&ipx_storage);

  //     assert!(ipx_per_epoch == 300, 0);

  //     test::return_shared(ipx_storage);
  //     test::return_to_sender(test, admin_cap);
  //   };
  // }

  // #[test]
  // fun test_update_ipx_per_epoch() {
  //   let scenario = scenario();
  //   test_update_ipx_per_epoch_(&mut scenario);
  //   test::end(scenario);
  // }

  // fun test_set_allocation_points_(test: &mut Scenario) {
  //   let (owner, _) = people();

  //   register_token(test);

  //   next_tx(test, owner);
  //   {
  //     let ipx_storage = test::take_shared<IPXStorage>(test);
  //     let admin_cap = test::take_from_sender<IPXAdmin>(test);
  //     let new_lo_coin_allocation_points = 400;

  //     ipx::set_allocation_points<LPCoin>(&admin_cap, &mut ipx_storage, new_lo_coin_allocation_points, false, ctx(test));

  //     let (lp_coin_allocation_points, last_reward_epoch, accrued_ipx_per_share, balance) = ipx::get_pool_info<LPCoin>(&ipx_storage);
  //     let (ipx_allocation_points, _, _, _) = ipx::get_pool_info<IPX>(&ipx_storage);
  //     let (_, _, total_allocation_points, _) = ipx::get_ipx_storage_info(&ipx_storage);

  //     let ipx_allocation = new_lo_coin_allocation_points / 3;

  //     assert!(lp_coin_allocation_points == new_lo_coin_allocation_points, 0);
  //     assert!(last_reward_epoch == START_EPOCH, 0);
  //     assert!(accrued_ipx_per_share == 0, 0);
  //     assert!(balance == 0, 0);
  //     assert!(ipx_allocation_points == ipx_allocation, 0);
  //     assert!(total_allocation_points == new_lo_coin_allocation_points + ipx_allocation, 0);

  //     test::return_shared(ipx_storage);
  //     test::return_to_sender(test, admin_cap);
  //   };    
  // }

  // #[test]
  // fun test_set_allocation_points() {
  //   let scenario = scenario();
  //   test_set_allocation_points_(&mut scenario);
  //   test::end(scenario);
  // }

  // fun test_update_pool_(test: &mut Scenario) {
  //   let (alice, _) = people();

  //   register_token(test);

  //   let deposit_amount = 500;
  //   next_tx(test, alice);
  //   {
  //     let ipx_storage = test::take_shared<IPXStorage>(test);
  //     let account_storage = test::take_shared<AccountStorage>(test);

  //     burn(ipx::stake<LPCoin>(&mut ipx_storage, &mut account_storage, mint<LPCoin>(deposit_amount, ctx(test)), ctx(test)));

  //     test::return_shared(ipx_storage);
  //     test::return_shared(account_storage);      
  //   };

  //   advance_epoch(test, alice, 8);
  //   next_tx(test, alice);
  //   {
  //     let ipx_storage = test::take_shared<IPXStorage>(test);

  //     let (pool_allocation, last_reward_epoch, accrued_ipx_per_share, _) = ipx::get_pool_info<LPCoin>(&ipx_storage);
  //     let (_, ipx_per_epoch, total_allocation_points, _) = ipx::get_ipx_storage_info(&ipx_storage);

  //     assert!(last_reward_epoch == START_EPOCH, 0);
  //     assert!(accrued_ipx_per_share == 0, 0);

  //     ipx::update_pool<LPCoin>(&mut ipx_storage, ctx(test));

  //     let (_, last_reward_epoch_2, accrued_ipx_per_share_2, _) = ipx::get_pool_info<LPCoin>(&ipx_storage);
  //     let epoch2 = tx_context::epoch(ctx(test));

  //     assert!(last_reward_epoch_2 == epoch2, 0);
  //     assert!(accrued_ipx_per_share_2 == (((pool_allocation * (epoch2 - last_reward_epoch) * ipx_per_epoch  / total_allocation_points) / 500) as u256), 0);

  //     test::return_shared(ipx_storage);
  //   }
  // }

  // #[test]
  // fun test_update_pool() {
  //   let scenario = scenario();
  //   test_update_pool_(&mut scenario);
  //   test::end(scenario);
  // }

  // fun test_update_pools_(test: &mut Scenario) {
  //   let (alice, _) = people();
     
  //    // Register first token
  //    register_token(test);
     
  //    // Register second token
  //    next_tx(test, alice);
  //    {
  //     let ipx_storage = test::take_shared<IPXStorage>(test);
  //     let admin_cap = test::take_from_sender<IPXAdmin>(test);
  //     let account_storage = test::take_shared<AccountStorage>(test);

  //     ipx::add_pool<LPCoin2>(&admin_cap, &mut ipx_storage, &mut account_storage, 800, false, ctx(test));

  //     test::return_shared(ipx_storage);
  //     test::return_to_sender(test, admin_cap);
  //     test::return_shared(account_storage);
  //    };

  //   let deposit_amount = 500;
  //   next_tx(test, alice);
  //   {
  //     let ipx_storage = test::take_shared<IPXStorage>(test);
  //     let account_storage = test::take_shared<AccountStorage>(test);

  //     burn(ipx::stake<LPCoin>(&mut ipx_storage, &mut account_storage, mint<LPCoin>(deposit_amount, ctx(test)), ctx(test)));
  //     burn(ipx::stake<LPCoin2>(&mut ipx_storage, &mut account_storage, mint<LPCoin2>(deposit_amount * 2, ctx(test)), ctx(test)));

  //     test::return_shared(ipx_storage);
  //     test::return_shared(account_storage);      
  //   };

  //   advance_epoch(test, alice, 10);
  //   next_tx(test, alice);
  //   {
  //     let ipx_storage = test::take_shared<IPXStorage>(test);

  //     ipx::update_pool<LPCoin>(&mut ipx_storage, ctx(test));
  //     ipx::update_pool<LPCoin2>(&mut ipx_storage, ctx(test));

  //     let (_, ipx_per_epoch, total_allocation_points, _) = ipx::get_ipx_storage_info(&ipx_storage);
  //     let (lp_coin_pool_allocation, lp_coin_last_reward_epoch, lp_coin_accrued_ipx_per_share, _) = ipx::get_pool_info<LPCoin>(&ipx_storage);
  //     let (lp_coin_2_pool_allocation, lp_coin_2_last_reward_epoch, lp_coin_2_accrued_ipx_per_share, _) = ipx::get_pool_info<LPCoin2>(&ipx_storage);

  //     assert!(lp_coin_last_reward_epoch == 10, 0);
  //     assert!(lp_coin_2_last_reward_epoch == 10, 0);
  //     assert!(lp_coin_accrued_ipx_per_share == (((lp_coin_pool_allocation * (10 - 4) * ipx_per_epoch  / total_allocation_points) / 500) as u256), 0);
  //     assert!(lp_coin_2_accrued_ipx_per_share == (((lp_coin_2_pool_allocation * (10 - 4) * ipx_per_epoch  / total_allocation_points) / 1000) as u256), 0);

  //     test::return_shared(ipx_storage);
  //   }
  // }

  // #[test]
  // fun test_update_pools() {
  //   let scenario = scenario();
  //   test_update_pools_(&mut scenario);
  //   test::end(scenario);
  // }

  fun register_token(test: &mut Scenario) {
    let (owner, _) = people();

    next_tx(test, owner);
    {
      master_chef::init_for_testing(ctx(test));
      ipx::init_for_testing(ctx(test));
      clock::create_for_testing(ctx(test));
    };

    next_tx(test, owner);
    {
      let master_chef_storage = test::take_shared<MasterChefStorage>(test);
      let admin_cap = test::take_from_sender<MasterChefAdmin>(test);
      let account_storage = test::take_shared<AccountStorage>(test);
      let clock_object = test::take_shared<Clock>(test);

      master_chef::add_pool<LPCoin>(
        &admin_cap, 
        &mut master_chef_storage, 
        &mut account_storage, 
        &clock_object,
        LPCOIN_ALLOCATION_POINTS, 
        false, 
        ctx(test)
      );

      test::return_shared(clock_object);
      test::return_shared(master_chef_storage);
      test::return_to_sender(test, admin_cap);
      test::return_shared(account_storage);
    };
  }
}