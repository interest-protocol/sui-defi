#[test_only]
module airdrop::airdrop_tests {

  use sui::coin::{mint_for_testing as mint};
  use sui::test_scenario::{Self as test, Scenario, next_tx, ctx};
  use sui::test_utils::{assert_eq};  
  
  use airdrop::core::{Self, AirdropAdminCap, AirdropStorage};

  use ipx::ipx::{IPX};

  use library::test_utils::{people, scenario};

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

      let root = x"aea2dd4249dcecf97ca6a1556db7f21ebd6a40bbec0243ca61b717146a08c347";
      
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
}