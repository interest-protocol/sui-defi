#[test_only]
module airdrop::airdrop_tests {
  use std::vector;

  use sui::coin::{mint_for_testing as mint, burn_for_testing as burn};
  use sui::test_scenario::{Self as test, Scenario, next_tx, ctx};
  use sui::test_utils::{assert_eq};
  use sui::clock;  
  
  use airdrop::core::{Self, AirdropAdminCap, AirdropStorage};

  use ipx::ipx::{IPX};

  use library::test_utils::{scenario};

  const START_TIME: u64 = 100;

  fun set_up(test: &mut Scenario) {

    let (alice, _) = people();
    
    next_tx(test, alice);
    {
    core::init_for_testing(ctx(test));
    };
  }

  #[test]
  fun test_start() {
    let scenario = scenario();

    let test = &mut scenario;

    let (alice, _) = people();

    set_up(test);
    
    next_tx(test, alice);
    {
      let admin_cap = test::take_from_address<AirdropAdminCap>(test, alice);
      let storage = test::take_shared<AirdropStorage>(test);    

      let root = x"59d3298db60c8c3ea35d3de0f43e297df7f27d8c3ba02555bcd7a2eee106aace";
      
      core::start(&admin_cap, &mut storage, root, mint<IPX>(200, ctx(test)), START_TIME);

      let (balance_value, saved_root, start_time) = core::read_storage(&storage);

      assert_eq(balance_value, 200);
      assert_eq(saved_root, root);
      assert_eq(start_time, START_TIME);

      test::return_to_sender(test, admin_cap);
      test::return_shared(storage);
    };
    test::end(scenario);
  }

  #[test]
  fun test_get_airdrop() {
    let scenario = scenario();

    let test = &mut scenario;

    let (alice, _) = people();

    set_up(test);

    let root = x"59d3298db60c8c3ea35d3de0f43e297df7f27d8c3ba02555bcd7a2eee106aace";
    let alice_proof = x"f99692a8fccf12eb2bf6399f23bf9379e38a98367a75e250d53eb727c1385624";

    let duration = core::get_duration();
    let clock_object = clock::create_for_testing(ctx(test));
    let proof = vector::empty<vector<u8>>();
    vector::push_back(&mut proof, alice_proof);


    let alice_amount = 55;
    
    next_tx(test, alice);
    {
      let admin_cap = test::take_from_address<AirdropAdminCap>(test, alice);
      let storage = test::take_shared<AirdropStorage>(test);    
      
      core::start(&admin_cap, &mut storage, root, mint<IPX>(200, ctx(test)), START_TIME);

      test::return_to_sender(test, admin_cap);
      test::return_shared(storage); 
    };

    next_tx(test, alice);
    {
      let storage = test::take_shared<AirdropStorage>(test);    
  
      assert_eq(burn(core::get_airdrop(&mut storage, &clock_object, proof, alice_amount, ctx(test))), 0);
      assert_eq(core::read_account(&storage, alice), 0);

      test::return_shared(storage);       
    };

    next_tx(test, alice);
    {
      let storage = test::take_shared<AirdropStorage>(test);    
      
      clock::set_for_testing(&mut clock_object, START_TIME + (duration / 5));

      assert_eq(burn(core::get_airdrop(&mut storage, &clock_object, proof, alice_amount, ctx(test))), alice_amount / 5);
      assert_eq(burn(core::get_airdrop(&mut storage, &clock_object, proof, alice_amount, ctx(test))), 0);
      assert_eq(core::read_account(&storage, alice), alice_amount / 5);

      test::return_shared(storage);       
    };

    next_tx(test, alice);
    {
      let storage = test::take_shared<AirdropStorage>(test);    
      
      clock::set_for_testing(&mut clock_object, START_TIME + duration);

      assert_eq(burn(core::get_airdrop(&mut storage, &clock_object, proof, alice_amount, ctx(test))), alice_amount - (alice_amount / 5));
      assert_eq(core::read_account(&storage, alice), alice_amount);

      test::return_shared(storage);       
    };

    clock::destroy_for_testing(clock_object);
    test::end(scenario);   
  }

  #[test]
  #[expected_failure(abort_code = airdrop::core::ERROR_NOT_STARTED)]
  fun test_get_airdrop_start_error() {
    let scenario = scenario();

    let test = &mut scenario;

    let (alice, _) = people();

    set_up(test);

    let alice_proof = x"f99692a8fccf12eb2bf6399f23bf9379e38a98367a75e250d53eb727c1385624";

    let clock_object = clock::create_for_testing(ctx(test));
    let proof = vector::empty<vector<u8>>();
    vector::push_back(&mut proof, alice_proof);

    let alice_amount = 55;
    
    next_tx(test, alice);
    {
      let storage = test::take_shared<AirdropStorage>(test);    
      
      burn(core::get_airdrop(&mut storage, &clock_object, proof, alice_amount, ctx(test)));

      test::return_shared(storage);          
    };

    clock::destroy_for_testing(clock_object);
    test::end(scenario);   
  }

  #[test]
  #[expected_failure(abort_code = airdrop::core::ERROR_NO_ROOT)]
  fun test_get_airdrop_no_root_error() {
    let scenario = scenario();

    let test = &mut scenario;

    let (alice, _) = people();

    set_up(test);

    let alice_proof = x"f99692a8fccf12eb2bf6399f23bf9379e38a98367a75e250d53eb727c1385624";

    let clock_object = clock::create_for_testing(ctx(test));
    let proof = vector::empty<vector<u8>>();
    vector::push_back(&mut proof, alice_proof);

    let alice_amount = 55;

    next_tx(test, alice);
    {
      let admin_cap = test::take_from_address<AirdropAdminCap>(test, alice);
      let storage = test::take_shared<AirdropStorage>(test);    
      
      core::start(&admin_cap, &mut storage, x"", mint<IPX>(200, ctx(test)), START_TIME);

      test::return_to_sender(test, admin_cap);
      test::return_shared(storage); 
    };
    
    next_tx(test, alice);
    {
      let storage = test::take_shared<AirdropStorage>(test);    
      
      burn(core::get_airdrop(&mut storage, &clock_object, proof, alice_amount, ctx(test)));

      test::return_shared(storage);          
    };

    clock::destroy_for_testing(clock_object);
    test::end(scenario);   
  }

  #[test]
  #[expected_failure(abort_code = airdrop::core::ERROR_INVALID_PROOF)]
  fun test_get_airdrop_invalid_proof_error() {
    let scenario = scenario();

    let test = &mut scenario;

    let (alice, _) = people();

    set_up(test);

    let root = x"59d3298db60c8c3ea35d3de0f43e297df7f27d8c3ba02555bcd7a2eee106aace";
    let alice_proof = x"f99692a8fccf12eb2bf6399f23bf9379e38a98367a75e250d53eb727c1385624";

    let clock_object = clock::create_for_testing(ctx(test));
    let proof = vector::empty<vector<u8>>();
    vector::push_back(&mut proof, alice_proof);


    let alice_amount = 56;
    
    next_tx(test, alice);
    {
      let admin_cap = test::take_from_address<AirdropAdminCap>(test, alice);
      let storage = test::take_shared<AirdropStorage>(test);    
      
      core::start(&admin_cap, &mut storage, root, mint<IPX>(200, ctx(test)), START_TIME);

      test::return_to_sender(test, admin_cap);
      test::return_shared(storage); 
    };

    next_tx(test, alice);
    {
      let storage = test::take_shared<AirdropStorage>(test);    
  
      assert_eq(burn(core::get_airdrop(&mut storage, &clock_object, proof, alice_amount, ctx(test))), 0);
      assert_eq(core::read_account(&storage, alice), 0);

      test::return_shared(storage);       
    };

    clock::destroy_for_testing(clock_object);
    test::end(scenario);   
  }

    #[test]
  #[expected_failure(abort_code = airdrop::core::ERROR_ALL_CLAIMED)]
  fun test_get_airdrop_all_claimed_error() {
    let scenario = scenario();

    let test = &mut scenario;

    let (alice, _) = people();

    set_up(test);

    let root = x"59d3298db60c8c3ea35d3de0f43e297df7f27d8c3ba02555bcd7a2eee106aace";
    let alice_proof = x"f99692a8fccf12eb2bf6399f23bf9379e38a98367a75e250d53eb727c1385624";

    let duration = core::get_duration();
    let clock_object = clock::create_for_testing(ctx(test));
    let proof = vector::empty<vector<u8>>();
    vector::push_back(&mut proof, alice_proof);


    let alice_amount = 55;
    
    next_tx(test, alice);
    {
      let admin_cap = test::take_from_address<AirdropAdminCap>(test, alice);
      let storage = test::take_shared<AirdropStorage>(test);    
      
      core::start(&admin_cap, &mut storage, root, mint<IPX>(200, ctx(test)), START_TIME);

      test::return_to_sender(test, admin_cap);
      test::return_shared(storage); 
    };

    next_tx(test, alice);
    {
      let storage = test::take_shared<AirdropStorage>(test);    
      
      clock::set_for_testing(&mut clock_object, START_TIME + duration);

      burn(core::get_airdrop(&mut storage, &clock_object, proof, alice_amount, ctx(test)));
      burn(core::get_airdrop(&mut storage, &clock_object, proof, alice_amount, ctx(test)));

      test::return_shared(storage);       
    };


    clock::destroy_for_testing(clock_object);
    test::end(scenario);   
  }


  public fun people():(address, address) { (
    @0x94fbcf49867fd909e6b2ecf2802c4b2bba7c9b2d50a13abbb75dbae0216db82a, 
    @0xb4536519beaef9d9207af2b5f83ae35d4ac76cc288ab9004b39254b354149d27
    )
  }
}