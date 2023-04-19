#[test_only]
module dex::curve_tests {
  use sui::test_scenario::{Self as test, next_tx};
  use sui::test_utils::{assert_eq};

  use dex::curve::{Self, Volatile, Stable};
  use library::test_utils::{people, scenario};

  struct Test {}

  #[test]
  fun test_is_curve() {
    let scenario = scenario();

    let test = &mut scenario;

    let (alice, _) = people();

    next_tx(test, alice);
    {
      assert_eq(curve::is_curve<Volatile>(), true);
      assert_eq(curve::is_curve<Stable>(), true);
      assert_eq(curve::is_curve<Test>(), false);
    };  

    test::end(scenario);
  }

  #[test]
  fun test_is_volatile() {
    let scenario = scenario();

    let test = &mut scenario;

    let (alice, _) = people();

    next_tx(test, alice);
    {
      assert_eq(curve::is_volatile<Volatile>(), true);
      assert_eq(curve::is_volatile<Stable>(), false);
      assert_eq(curve::is_volatile<Test>(), false);
    };  

    test::end(scenario);    
  }

}