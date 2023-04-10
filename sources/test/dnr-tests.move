#[test_only]
module interest_protocol::dnr_tests {
  use sui::test_scenario::{Self as test, next_tx, Scenario, ctx};
  use sui::test_utils::{assert_eq};
  use sui::coin::{burn_for_testing as burn};

  use interest_protocol::dnr::{Self, DineroStorage, DineroAdminCap};
  use interest_protocol::test_utils::{people, scenario};
  use interest_protocol::foo::{Self, FooStorage};


  #[test]
  #[expected_failure(abort_code = dnr::ERROR_NOT_ALLOWED_TO_MINT)]
  fun test_mint_amount_error() {
      let scenario = scenario();
      let (alice, _) = people();
      let test = &mut scenario;

      start_dnr(test);

      next_tx(test, alice);
      {
        let dnr_storage = test::take_shared<DineroStorage>(test);
        let foo_storage = test::take_shared<FooStorage>(test);

        let publisher = foo::get_publisher(&foo_storage);
        let id = foo::get_publisher_id(&foo_storage);

        burn(dnr::mint(&mut dnr_storage, publisher, 1, ctx(test)));

        assert_eq(dnr::is_minter(&dnr_storage, id), true);

        test::return_shared(dnr_storage);
        test::return_shared(foo_storage);
      };
      test::end(scenario);
  }

  #[test]
  fun test_mint() {
      let scenario = scenario();
      let (alice, _) = people();
      let test = &mut scenario;

      start_dnr(test);

      next_tx(test, alice);
      {
        let dnr_storage = test::take_shared<DineroStorage>(test);
        let foo_storage = test::take_shared<FooStorage>(test);
        let admin_cap = test::take_from_address<DineroAdminCap>(test, alice);

        let publisher = foo::get_publisher(&foo_storage);
        let id = foo::get_publisher_id(&foo_storage);


        dnr::add_minter(&admin_cap, &mut dnr_storage, id);
        assert_eq(burn(dnr::mint(&mut dnr_storage, publisher, 100, ctx(test))), 100);


        test::return_shared(dnr_storage);
        test::return_shared(foo_storage);
        test::return_to_address(alice, admin_cap);
      };
      test::end(scenario);
  }
  
  #[test]
  #[expected_failure(abort_code = dnr::ERROR_NOT_ALLOWED_TO_MINT)]
  fun test_remove_minter() {
      let scenario = scenario();
      let (alice, _) = people();
      let test = &mut scenario;

      start_dnr(test);

      next_tx(test, alice);
      {
        let dnr_storage = test::take_shared<DineroStorage>(test);
        let foo_storage = test::take_shared<FooStorage>(test);
        let admin_cap = test::take_from_address<DineroAdminCap>(test, alice);

        let publisher = foo::get_publisher(&foo_storage);
        let id = foo::get_publisher_id(&foo_storage);


        dnr::add_minter(&admin_cap, &mut dnr_storage, id);
        assert_eq(burn(dnr::mint(&mut dnr_storage, publisher, 100, ctx(test))), 100);

        dnr::remove_minter(&admin_cap, &mut dnr_storage, id);

        assert_eq(dnr::is_minter(&dnr_storage, id), false);
        assert_eq(burn(dnr::mint(&mut dnr_storage, publisher, 100, ctx(test))), 100);

        test::return_shared(dnr_storage);
        test::return_shared(foo_storage);
        test::return_to_address(alice, admin_cap);
      };
      test::end(scenario);
  }

  #[test]
  fun test_burn() {
      let scenario = scenario();
      let (alice, _) = people();
      let test = &mut scenario;

      start_dnr(test);

      next_tx(test, alice);
      {
        let dnr_storage = test::take_shared<DineroStorage>(test);
        let foo_storage = test::take_shared<FooStorage>(test);
        let admin_cap = test::take_from_address<DineroAdminCap>(test, alice);

        let publisher = foo::get_publisher(&foo_storage);
        let id = foo::get_publisher_id(&foo_storage);


        dnr::add_minter(&admin_cap, &mut dnr_storage, id);

        let coin_ipx = dnr::mint(&mut dnr_storage, publisher, 100, ctx(test));
        assert_eq(dnr::burn(&mut dnr_storage, coin_ipx), 100);


        test::return_shared(dnr_storage);
        test::return_shared(foo_storage);
        test::return_to_address(alice, admin_cap);
      };
      test::end(scenario);
  }

  fun start_dnr(test: &mut Scenario) {
       let (alice, _) = people();
       next_tx(test, alice);
       {
        dnr::init_for_testing(ctx(test));
        foo::init_for_testing(ctx(test));
       };
  }
}