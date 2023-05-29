#[test_only]
module clamm::test_utils {
  
  use sui::test_scenario::{Self as test, Scenario};

  use clamm::math128;

  public fun scenario(): Scenario { test::begin(@0x1) }

  public fun people():(address, address) { (@0xBEEF, @0x1337)}

  public fun create_sqrt_price(value: u128): u128 {
    math128::sqrt(value << 64)
  }
}