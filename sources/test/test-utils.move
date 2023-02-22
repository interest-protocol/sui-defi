#[test_only]
module interest_protocol::test_utils {
  
  use sui::test_scenario::{Self as test, Scenario, next_epoch};
  use sui::coin::{mint_for_testing, Coin};
  use sui::tx_context::{TxContext};
  use sui::math;

  public fun scenario(): Scenario { test::begin(@0x1) }

  public fun people():(address, address) { (@0xBEEF, @0x1337)}

  public fun mint<T>(amount: u64, decimals: u8, ctx: &mut TxContext): Coin<T> {
    mint_for_testing<T>(amount * math::pow(10, decimals), ctx)
  }

  public fun advance_epoch(test: &mut Scenario, sender: address, num_of_epochs: u64) {
    let index = 0;

    while (index < num_of_epochs) {
      next_epoch(test, sender);
      index = index + 1;
    }
  }
}