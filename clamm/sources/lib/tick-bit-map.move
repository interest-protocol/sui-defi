// Taken from https://github.com/Uniswap/v3-core/blob/main/contracts/libraries/TickBitmap.sol
module clamm::tick_bit_map {

  use sui::table::{Self, Table};

  use i256::i256::{shr, mod, I256, truncate_to_u8, from, div, is_neg, is_zero, sub, one, mul, add};

  #[test_only]
  use i256::i256::{compare};

  use clamm::bit_math::{least_significant_bit, most_significant_bit};

  const MAX_U256: u256 = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;

  const ERROR_FLIPPING: u64 = 0;

  struct State has store {
    bits: u256
  }

  public fun position(tick: &I256): (I256, u8) {
    (shr(tick, 8), truncate_to_u8(&mod(tick, &from(256))))
  }

  public fun flip_tick(bit_map: &mut Table<I256, State>, tick: &I256, tick_spacing: &I256) {
    assert!(is_zero(&mod(tick, tick_spacing)), ERROR_FLIPPING);
    let (word, bit) = position(&div(tick, tick_spacing));
    let mask: u256 = 1 << bit;
    let state = borrow_mut_state(bit_map, word);
    state.bits = state.bits ^ mask;
  }

  public fun next_initialized_tick_within_one_word(
    bit_map: &mut Table<I256, State>,
    tick: &I256,
    tick_spacing: &I256,
    lte: bool
  ): (I256, bool) {
    let compressed = div(tick, tick_spacing);
    if (is_neg(tick) && !is_zero(&mod(tick, tick_spacing))) compressed = sub(&compressed, &one());

    if (lte) {
      let (word, bit) = position(&compressed);
    
      let mask = ((1 << bit) - 1 + (1 << bit));
      let state = borrow_mut_state(bit_map, word);
      let masked = state.bits & mask; 

      if (masked != 0) {
          (mul(&sub(&compressed, &from((bit - most_significant_bit(masked) as u256))), tick_spacing), true)
      } else {
        (mul(&sub(&compressed, &from((bit as u256))), tick_spacing), false)
      }
    } else {
      let (word, bit) = position(&add(&compressed, &one()));

      let state = borrow_mut_state(bit_map, word);
      let masked = state.bits & (((1 << bit) - 1) ^ MAX_U256); 

      if (masked != 0) {
         (mul(&add(&add(&compressed, &one()), &from(((least_significant_bit(masked) - bit) as u256))), tick_spacing), true)
      } else {
        (mul(&add(&add(&compressed, &one()), &from(((255 - bit) as u256))), tick_spacing), false)
      }
    }
  }

  fun borrow_mut_state(bit_map: &mut Table<I256, State>, word: I256): &mut State {
    if (!table::contains(bit_map, word)) {
      table::add(bit_map, word, State { bits: 0 });
    };
    table::borrow_mut(bit_map, word)
  }

  #[test_only]
  public fun test_flip_tick(bit_map: &mut Table<I256, State>, tick: &I256) {
    flip_tick(bit_map, tick, &one());
  }

  #[test_only]
  public fun test_next_initialized_tick_within_one_word(
    bit_map: &mut Table<I256, State>,
    tick: &I256,
    lte: bool
  ): (I256, bool) {
    next_initialized_tick_within_one_word(bit_map, tick, &one(), lte)
  }
  
  #[test_only]
  public fun test_is_initialized(bit_map: &mut Table<I256, State>, tick: &I256): bool {
    let (next, initialized) = next_initialized_tick_within_one_word(bit_map, tick, &one(), true);
    if (compare(&next, tick) == 0) { initialized } else { false }
  }
}