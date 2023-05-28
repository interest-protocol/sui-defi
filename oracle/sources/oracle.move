module oracle::oracle {
  use std::ascii::{String};
  
  use sui::clock::{Self, Clock};
  use sui::object::{UID};
  use sui::bag::{Self, Bag};
  use sui::vec_map::{Self, VecMap};

  use switchboard_std::aggregator::{Self, Aggregator};
  use library::utils::{get_coin_info_string};

  const ERROR_SWITCHBOARD_ORACLE_OUTDATED: u64 = 1;
  const ERROR_PYTH_ORACLE_OUTDATED: u64 = 2;
  const ERROR_IMPOSSIBLE_PRICE: u64 = 3;

  struct AdminCap has key {
    id: UID
  }

  struct Price has store {
    switchboard_result: u256,
    pyth_result: u256,
    pyth_timestamp: u64,
    switchboard_timestamp: u64,
    result: u256,
  }

  struct SwitchboardFeedAddress has store {
    value: address
  }

  struct OracleStorage {
     id: UID,
     price_bag: Bag,
     switchboard_feed: VecMap<String, SwitchboardFeedAddress>
  }

  entry fun update_oracle() {}

  public fun get_price<T>(storage: &OracleStorage, clock_object: &Clock): u256 {
    let current_ms = clock::timestamp_ms(clock_object);
    let coin_name = get_coin_info_string<T>();

    let price = bag::borrow<String, Price>(&storage.price_bag, coin_name);

    // Need to make sure the prices are up to date on the same transaction block.
    assert!(price.switchboard_timestamp == current_ms, ERROR_SWITCHBOARD_ORACLE_OUTDATED);
    assert!(price.pyth_timestamp == current_ms, ERROR_PYTH_ORACLE_OUTDATED);
    // Revert if the price is 0
    assert!(price.switchboard_result != 0, ERROR_IMPOSSIBLE_PRICE);
    assert!(price.pyth_result != 0, ERROR_IMPOSSIBLE_PRICE);
    assert!(price.result != 0, ERROR_IMPOSSIBLE_PRICE);
    
    price.result
  }

  entry fun set_switchboard_feed<T>(_:& AdminCap, storage: &mut OracleStorage, feed: &Aggregator) {
    let coin_name = get_coin_info_string<T>();

    let feed_address = aggregator::aggregator_address(feed);

    if (vec_map::contains(&storage.switchboard_feed, &coin_name)) {
      let switchboard_feed_address = vec_map::get_mut(&mut storage.switchboard_feed, &coin_name);
      switchboard_feed_address.value = feed_address ;
      bag::add(&mut storage.price_bag, coin_name, Price{ 
           switchboard_result: 0,
           pyth_result: 0,
           pyth_timestamp: 0,
           switchboard_timestamp: 0,
           result: 0,
        });
    } else {
      vec_map::insert(&mut storage.switchboard_feed, coin_name, SwitchboardFeedAddress { value: feed_address });
    };
  }
}