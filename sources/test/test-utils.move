#[test_only]
module interest_protocol::test_utils {
  use sui::test_scenario::{Self as test, Scenario};

  public fun scenario(): Scenario { test::begin(@0x1) }

  public fun people():(address, address) { (@0xBEEF, @0x1337)}
}