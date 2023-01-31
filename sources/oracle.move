module whirpool::oracle {
  use std::ascii::{String}; 

  use sui::tx_context::{Self, TxContext};
  use sui::transfer;
  use sui::object::{Self, UID};
  use sui::table::{Self, Table};

  use whirpool::utils::{get_coin_info};

  struct AdminCap has key {
    id: UID,
  }

  struct PriceData has key, store {
    id: UID,
    price: u256,
    decimals: u8
  }

  struct Oracle has key {
      id: UID,
      price_table: Table<String, PriceData>
  }

  fun init(ctx: &mut TxContext) {
      transfer::transfer(
        AdminCap { 
          id: object::new(ctx)
        }, 
        tx_context::sender(ctx)
      );

      transfer::share_object(
        Oracle {
          id: object::new(ctx),
          price_table: table::new<String, PriceData>(ctx)
        }
      );
  }

  public fun set_price<T>(
    _: &AdminCap,
    oracle: &mut Oracle, 
    price: u256, 
    decimals: u8
    
    ) {
      let data = table::borrow_mut(&mut oracle.price_table, get_coin_info<T>());

      data.price = price;
      data.decimals = decimals;
  }

  public fun get_price<T>(oracle: &Oracle): &PriceData  {
    table::borrow(&oracle.price_table, get_coin_info<T>())
  }
}