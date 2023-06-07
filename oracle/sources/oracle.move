module oracle::oracle {

  use std::ascii::{String};
  
  use sui::clock::{Self, Clock};
  use sui::object::{Self, UID};
  use sui::vec_map::{Self, VecMap};
  use sui::tx_context::{Self, TxContext};
  use sui::transfer;
  use sui::event::{emit};
  use sui::math::{pow};

  use oracle::lib::{get_struct_name_string, mul_div, average};

  use pyth::pyth::{get_price as pyth_get_price};
  use pyth::state::{State as PythState};
  use pyth::price_info::{PriceInfoObject};
  use pyth::price::{Self as pyth_price};
  use pyth::i64;

  use switchboard_std::aggregator::{Self, Aggregator};
  use switchboard_std::math;

  const SCALAR: u256 = 1000000000000000000;
  const PRICE_MARGIN: u256 = 20000000000000000; // 0.02e18 It represents 2%

  const ERROR_SWITCHBOARD_ORACLE_OUTDATED: u64 = 1;
  const ERROR_PYTH_ORACLE_OUTDATED: u64 = 2;
  const ERROR_IMPOSSIBLE_PRICE: u64 = 3;
  const ERROR_INVALID_ADMIN: u64 = 4;
  const ERROR_INVALID_SWITCHBOARD_FEED: u64 = 5;
  const ERROR_INVALID_TIME: u64 = 6;
  const ERROR_BAD_PRICES: u64 = 7;

  struct AdminCap has key {
    id: UID
  }

  struct SwitchboardFeedAddress has store {
    value: address
  }

  struct OracleStorage has key {
     id: UID,
     switchboard_feed: VecMap<String, SwitchboardFeedAddress>
  }

  struct NewAdmin has drop, copy {
    admin: address
  }

  struct NewSwitchboardFeed has drop, copy {
    feed: address,
    coin_name: String
  }

  struct GetPrice<phantom T> has copy, drop {
    sender: address,
    switchboard_result: u256,
    switchboard_timestamp: u64,
    pyth_timestamp: u64,
    pyth_result: u256,
  }

  // Hot Potato to be passed
  struct Price {
    switchboard_result: u256,
    pyth_result: u256,
    scalar: u256,
    pyth_timestamp: u64,
    switchboard_timestamp: u64,
    average: u256,
    coin_name: String
  }

  fun init(ctx: &mut TxContext) {
    transfer::transfer(
      AdminCap {
        id: object::new(ctx)
      },
      tx_context::sender(ctx)
    );

    transfer::share_object(
      OracleStorage {
        id: object::new(ctx),
        switchboard_feed: vec_map::empty()
      }
    );
  }

  public fun get_price<T>(
    storage: &mut OracleStorage, 
    state: &PythState,
    price_info_object: &PriceInfoObject,
    clock_object: &Clock,
    switchboard_feed: &Aggregator, 
    ctx: &mut TxContext
  ): Price {
    let coin_name = get_struct_name_string<T>();

    let authorized_switchboard_feed = vec_map::get(&mut storage.switchboard_feed, &coin_name);
    assert!(authorized_switchboard_feed.value == aggregator::aggregator_address(switchboard_feed), ERROR_INVALID_SWITCHBOARD_FEED);

    let (switchboard_result, switchboard_timestamp) = aggregator::latest_value(switchboard_feed);
    let (switchboard_value, switchboard_scaling_factor, _neg) = math::unpack(switchboard_result);

    assert!(switchboard_value > 0 && !_neg, ERROR_IMPOSSIBLE_PRICE);

    let pyth_price = pyth_get_price(state, price_info_object, clock_object);

    let pyth_price_value = pyth_price::get_price(&pyth_price);
    let pyth_price_expo = pyth_price::get_expo(&pyth_price);
    let pyth_price_timestamp = pyth_price::get_timestamp(&pyth_price);

    assert!(clock::timestamp_ms(clock_object) == pyth_price_timestamp, ERROR_INVALID_TIME);
    
    // will throw if negative
    let pyth_price_u64 = i64::get_magnitude_if_positive(&pyth_price_value);
    assert!(pyth_price_u64 > 0 && !_neg, ERROR_IMPOSSIBLE_PRICE);
    
    let pyth_exp_u64 = i64::get_magnitude_if_negative(&pyth_price_expo);

    let switchboard_result = mul_div((switchboard_value as u256), SCALAR, (pow(10, switchboard_scaling_factor) as u256));
    let pyth_result = mul_div((pyth_price_u64 as u256), SCALAR, (pow(10, (pyth_exp_u64 as u8)) as u256));

    let average = get_safe_average(switchboard_result, pyth_result);

    assert!(average > 0 && !_neg, ERROR_IMPOSSIBLE_PRICE);

    emit(GetPrice<T> { sender: tx_context::sender(ctx), switchboard_result, switchboard_timestamp, pyth_result, pyth_timestamp: pyth_price_timestamp });

    Price {
      switchboard_result,
      switchboard_timestamp,
      scalar: SCALAR,
      pyth_timestamp: pyth_price_timestamp,
      pyth_result,
      average: 0,
      coin_name
    }
  }

  public fun read_price(price: Price): (u256, u256, u256, u256, u64, u64, String) {
    let Price { switchboard_result, pyth_result, scalar, pyth_timestamp, switchboard_timestamp, average, coin_name } = price;
    (switchboard_result, pyth_result, scalar, average, pyth_timestamp, switchboard_timestamp, coin_name)
  }

  entry fun set_switchboard_feed<T>(_:& AdminCap, storage: &mut OracleStorage, feed: &Aggregator) {
    let coin_name = get_struct_name_string<T>();

    let feed_address = aggregator::aggregator_address(feed);

    if (vec_map::contains(&storage.switchboard_feed, &coin_name)) {
      let switchboard_feed_address = vec_map::get_mut(&mut storage.switchboard_feed, &coin_name);
      switchboard_feed_address.value = feed_address;
    } else {
      vec_map::insert(&mut storage.switchboard_feed, coin_name, SwitchboardFeedAddress { value: feed_address });
    };

    emit(NewSwitchboardFeed {
      feed: feed_address,
      coin_name
    });
  }

  entry fun set_switchboard_feed<T>(_:& AdminCap, storage: &mut OracleStorage, feed: &Aggregator) {
    let coin_name = get_struct_name_string<T>();

    let feed_address = aggregator::aggregator_address(feed);

    if (vec_map::contains(&storage.switchboard_feed, &coin_name)) {
      let switchboard_feed_address = vec_map::get_mut(&mut storage.switchboard_feed, &coin_name);
      switchboard_feed_address.value = feed_address;
    } else {
      vec_map::insert(&mut storage.switchboard_feed, coin_name, SwitchboardFeedAddress { value: feed_address });
    };

    emit(NewSwitchboardFeed {
      feed: feed_address,
      coin_name
    });
  }

  fun get_safe_average(x: u256, y:u256): u256 {
    if (x > y) {
      let diff = x - y;
      assert!(PRICE_MARGIN >= (diff * SCALAR) / x, ERROR_BAD_PRICES);
    }; 

    if (y > x) {
      let diff = y - x;
      assert!(PRICE_MARGIN >= (diff * SCALAR) / y, ERROR_BAD_PRICES);
    };

    average(x, y)
  }

  entry fun transfer_admin_cap(cap: AdminCap, recipient: address) {
    assert!(recipient != @0x0, ERROR_INVALID_ADMIN);
    transfer::transfer(cap, recipient);
    emit(NewAdmin { admin: recipient });
  }
}