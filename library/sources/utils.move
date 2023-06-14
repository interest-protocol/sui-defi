// Set of common utility functions for Interest Protocol packages
module library::utils {
    use std::type_name;
    use std::ascii::{Self, String};
    use std::vector;

    use sui::coin::{Self, Coin};
    use sui::tx_context::{Self, TxContext};
    use sui::pay;
    use sui::transfer;

    use library::comparator;

    const MS_PER_YEAR: u64 = 31536000000; 
    const EQUAL: u8 = 0;
    const SMALLER: u8 = 1;
    const GREATER: u8 = 2;

    const ERROR_SAME_TYPE: u64 = 1;

    public fun get_smaller_enum(): u8 {
        SMALLER
    }

    public fun get_greater_enum(): u8 {
        GREATER
    }

    public fun get_equal_enum(): u8 {
        EQUAL
    }

    public fun get_type_name_bytes<T>(): vector<u8> {
       let name = type_name::into_string(type_name::get<T>());
       ascii::into_bytes(name)
    }

    public fun get_type_name_string<T>(): String {
      type_name::into_string(type_name::get<T>())
    }

    fun compare_struct<X,Y>(): u8 {
        let struct_x_bytes = get_type_name_bytes<X>();
        let struct_y_bytes = get_type_name_bytes<Y>();
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

    public fun are_types_sorted<X,Y>(): bool {
      let compare_x_y: u8 = compare_struct<X, Y>();
      assert!(compare_x_y != get_equal_enum(), ERROR_SAME_TYPE);
      (compare_x_y == get_smaller_enum())
    }

    public fun get_ms_per_year(): u64 {
      MS_PER_YEAR
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

    public fun public_transfer_coin<T>(asset: Coin<T>, recipient: address) {
      if (coin::value(&asset) == 0) {
        coin::destroy_zero(asset);
      } else {
        transfer::public_transfer(asset, recipient);
      }
    }
}