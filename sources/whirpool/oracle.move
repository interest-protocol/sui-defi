module interest_protocol::oracle {
  use std::ascii::{String}; 

  use sui::tx_context::{Self, TxContext};
  use sui::transfer;
  use sui::object::{Self, UID};
  use sui::table::{Self, Table};

  use interest_protocol::utils::{get_coin_info_string};

  struct OracleAdminCap has key {
    id: UID,
  }

  struct PriceData has key, store {
    id: UID,
    price: u256,
    decimals: u8
  }

  struct OracleStorage has key {
      id: UID,
      price_table: Table<String, PriceData>
  }

  fun init(ctx: &mut TxContext) {
      transfer::transfer(
        OracleAdminCap { 
          id: object::new(ctx)
        }, 
        tx_context::sender(ctx)
      );

      transfer::share_object(
        OracleStorage {
          id: object::new(ctx),
          price_table: table::new<String, PriceData>(ctx)
        }
      );
  }

  public fun set_price<T>(
    _: &OracleAdminCap,
    storage: &mut OracleStorage, 
    price: u256, 
    decimals: u8,
    ctx: &mut TxContext
    ) {
      let key = get_coin_info_string<T>();

      if (table::contains(&storage.price_table, key)) {
        let data = table::borrow_mut(&mut storage.price_table, key);
        data.price = price;
        data.decimals = decimals;
      } else {
        table::add(&mut storage.price_table, key, PriceData {
          id: object::new(ctx),
          price,
          decimals
        });
      }
  }

  public fun get_price(storage: &OracleStorage, key: String): (u256, u8)  {
    let price_data = table::borrow(&storage.price_table, key);
    (price_data.price, price_data.decimals)
  }


  #[test_only]
  public fun init_for_testing(ctx: &mut TxContext) {
    init(ctx);
  }
}