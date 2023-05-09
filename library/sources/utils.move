// Set of common utility functions for Interest Protocol packages
module library::utils {
    use std::type_name;
    use std::ascii::{Self, String};
    use std::vector;

    use sui::coin::{Self, Coin};
    use sui::tx_context::{Self, TxContext};
    use sui::pay;

    use library::comparator;
    use library::math::{mul_div};

    const MS_PER_YEAR: u64 = 31536000000; 
    const EQUAL: u8 = 0;
    const SMALLER: u8 = 1;
    const GREATER: u8 = 2;
    const MAX_U_128: u256 = 1340282366920938463463374607431768211455;

    const ERROR_SAME_COIN: u64 = 1;
    const ERROR_UNSORTED_COINS: u64 = 2;

    public fun get_smaller_enum(): u8 {
        SMALLER
    }

    public fun get_greater_enum(): u8 {
        GREATER
    }

    public fun get_equal_enum(): u8 {
        EQUAL
    }

    public fun get_coin_info<T>(): vector<u8> {
       let name = type_name::into_string(type_name::get<T>());
       ascii::into_bytes(name)
    }

    public fun get_coin_info_string<T>(): String {
      type_name::into_string(type_name::get<T>())
    }

    fun compare_struct<X,Y>(): u8 {
        let struct_x_bytes: vector<u8> = get_coin_info<X>();
        let struct_y_bytes: vector<u8> = get_coin_info<Y>();
        if (comparator::is_greater_than(&comparator::compare_u8_vector(struct_x_bytes, struct_y_bytes))) {
            GREATER
        } else if (comparator::is_equal(&comparator::compare_u8_vector(struct_x_bytes, struct_y_bytes))) {
            EQUAL
        } else {
            SMALLER
        }
    }

    public fun are_types_equal<X, Y>(): bool {
      compare_struct<X, Y>() == EQUAL
    }   

    public fun are_coins_sorted<X,Y>(): bool {
      let compare_x_y: u8 = compare_struct<X, Y>();
      assert!(compare_x_y != get_equal_enum(), ERROR_SAME_COIN);
      (compare_x_y == get_smaller_enum())
    }

    public fun quote_liquidity(amount_a: u64, reserves_a: u64, reserves_b: u64): u64 {
      mul_div(amount_a, reserves_b, reserves_a)
    }

    public fun get_ms_per_year(): u64 {
      MS_PER_YEAR
    }

    public fun calculate_cumulative_balance(balance: u256, timestamp: u64, old_reserve_cumulative: u256): u256 {
      let result = (balance * (timestamp as u256)) + old_reserve_cumulative;

      while (result > MAX_U_128) {
        result = result - MAX_U_128;
      };

      result
    }

    public fun max_u_128(): u256 {
      MAX_U_128
    }

    public  fun handle_coin_vector<X>(
      vector_x: vector<Coin<X>>,
      coin_in_value: u64,
      ctx: &mut TxContext
    ): Coin<X> {
      let coin_x = coin::zero<X>(ctx);

      if (vector::is_empty(&vector_x)){
        vector::destroy_empty(vector_x);
        return coin_x
      };

      pay::join_vec(&mut coin_x, vector_x);

      let coin_x_value = coin::value(&coin_x);
      if (coin_x_value > coin_in_value) pay::split_and_transfer(&mut coin_x, coin_x_value - coin_in_value, tx_context::sender(ctx), ctx);

      coin_x
    }
}