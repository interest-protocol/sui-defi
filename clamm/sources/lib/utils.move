// Set of common utility functions for Interest Protocol packages
module clamm::utils {
    use std::type_name;
    use std::ascii::{Self, String};
    use std::vector;

    use sui::coin::{Self, Coin};
    use sui::tx_context::{Self, TxContext};
    use sui::pay;

    use clamm::comparator;

    const EQUAL: u8 = 0;
    const SMALLER: u8 = 1;
    const GREATER: u8 = 2;

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

    public fun get_struct_bytes_name<T>(): vector<u8> {
       let name = type_name::into_string(type_name::get<T>());
       ascii::into_bytes(name)
    }

    public fun get_struct_string_name<T>(): String {
      type_name::into_string(type_name::get<T>())
    }

    fun compare_struct<X,Y>(): u8 {
        let struct_x_bytes: vector<u8> = get_struct_bytes_name<X>();
        let struct_y_bytes: vector<u8> = get_struct_bytes_name<Y>();
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