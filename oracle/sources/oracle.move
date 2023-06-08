module oracle::oracle {

  use std::ascii::{String};
  use std::vector;
  
  use sui::clock::{Self, Clock};
  use sui::object::{Self, UID, ID};
  use sui::vec_map::{Self, VecMap};
  use sui::tx_context::{Self, TxContext};
  use sui::transfer;
  use sui::event::{emit};
  use sui::math::{pow};
  use sui::coin::{Self, Coin};
  use sui::sui::{SUI};

  use oracle::lib::{get_struct_name_string, mul_div, average};

  use pyth::pyth::{get_price as pyth_get_price, create_price_infos_hot_potato, update_single_price_feed};
  use pyth::state::{State as PythState};
  use pyth::price_info::{Self, PriceInfoObject};
  use pyth::price::{Self as pyth_price};
  use pyth::hot_potato_vector::{destroy};
  use pyth::i64;

  use wormhole::state::{State as WormholeState};
  use wormhole::vaa::{parse_and_verify};

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
  const ERROR_INVALID_PRICE_INFO_OBJECT_ID : u64 = 8;

  struct AdminCap has key {
    id: UID
  }

  struct SwitchboardFeedAddress has store {
    value: address
  }

  struct PythPriceInfoObjectId has store {
    value: ID
  }

  struct OracleStorage has key {
     id: UID,
     switchboard_feed: VecMap<String, SwitchboardFeedAddress>,
     pyth_price_info: VecMap<String, PythPriceInfoObjectId>
  }

  struct NewAdmin has drop, copy {
    admin: address
  }

  struct NewFeed has drop, copy {
    switchboard_feed: address,
    pyth_price_info_id: ID,
    coin_name: String
  }

  struct GetPrice<phantom T> has copy, drop {
    sender: address,
    switchboard_result: u256,
    switchboard_timestamp: u64,
    pyth_timestamp: u64,
    pyth_result: u256,
    pyth_fee_value: u64
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
        switchboard_feed: vec_map::empty(),
        pyth_price_info: vec_map::empty()
      }
    );
  }

  public fun get_price<T>(
    storage: &mut OracleStorage, 
    wormhole_state: &WormholeState,
    pyth_state: &PythState,
    buf: vector<u8>,
    price_info_object: &mut PriceInfoObject,
    pyth_fee: Coin<SUI>,
    clock_object: &Clock,
    switchboard_feed: &Aggregator, 
    ctx: &mut TxContext
  ): Price {

    let coin_name = get_struct_name_string<T>();
    let pyth_fee_value = coin::value(&pyth_fee);

    let (switchboard_result, switchboard_timestamp) = get_switchboard_data(&storage.switchboard_feed, switchboard_feed, coin_name);
    let (pyth_result, pyth_timestamp) = get_pyth_network_data(
      &storage.pyth_price_info,
      wormhole_state,pyth_state,
      buf,
      price_info_object,
      pyth_fee,
      clock_object,
      coin_name
    );

    let average = get_safe_average(switchboard_result, pyth_result);

    assert!(average != 0, ERROR_IMPOSSIBLE_PRICE);

    emit(GetPrice<T> { sender: tx_context::sender(ctx), switchboard_result, switchboard_timestamp, pyth_result, pyth_timestamp, pyth_fee_value });

    Price {
      switchboard_result,
      switchboard_timestamp,
      scalar: SCALAR,
      pyth_timestamp,
      pyth_result,
      average,
      coin_name
    }
  }

  public fun read_price(price: Price): (u256, u256, u256, u256, u64, u64, String) {
    let Price { switchboard_result, pyth_result, scalar, pyth_timestamp, switchboard_timestamp, average, coin_name } = price;
    (switchboard_result, pyth_result, scalar, average, pyth_timestamp, switchboard_timestamp, coin_name)
  }

  entry fun set_feed<T>(
    _:& AdminCap, 
    storage: &mut OracleStorage, 
    switchboard_aggregator: &Aggregator,
    price_info_object: &PriceInfoObject
  ) {
    let coin_name = get_struct_name_string<T>();
    let pyth_price_info_id = price_info::uid_to_inner(price_info_object);
    let aggregator_address = aggregator::aggregator_address(switchboard_aggregator);

    if (vec_map::contains(&storage.switchboard_feed, &coin_name)) {
      let switchboard_feed_address = vec_map::get_mut(&mut storage.switchboard_feed, &coin_name);
      switchboard_feed_address.value = aggregator_address ;
    } else {
      vec_map::insert(&mut storage.switchboard_feed, coin_name, SwitchboardFeedAddress { value: aggregator_address });
    };

    if (vec_map::contains(&storage.pyth_price_info, &coin_name)) {
      let pyth_price_info_struct = vec_map::get_mut(&mut storage.pyth_price_info, &coin_name);
      pyth_price_info_struct.value = pyth_price_info_id;
    } else {
      vec_map::insert(&mut storage.pyth_price_info, coin_name, PythPriceInfoObjectId { value: pyth_price_info_id });
    };

    emit(NewFeed {
      switchboard_feed: aggregator_address,
      pyth_price_info_id,
      coin_name
    });
  }

  fun get_switchboard_data(
    feed_map: &VecMap<String, SwitchboardFeedAddress>,
    switchboard_feed: &Aggregator,
    coin_name: String
  ): (u256, u64) {
    
    let authorized_switchboard_feed = vec_map::get(feed_map, &coin_name);

    assert!(authorized_switchboard_feed.value == aggregator::aggregator_address(switchboard_feed), ERROR_INVALID_SWITCHBOARD_FEED);

    let (switchboard_result, switchboard_timestamp) = aggregator::latest_value(switchboard_feed);
    let (switchboard_value, switchboard_scaling_factor, _neg) = math::unpack(switchboard_result);

    assert!(switchboard_value > 0 && !_neg, ERROR_IMPOSSIBLE_PRICE);

    (mul_div((switchboard_value as u256), SCALAR, (pow(10, switchboard_scaling_factor) as u256)), switchboard_timestamp)
  }

  fun get_pyth_network_data(
    price_info_map: &VecMap<String, PythPriceInfoObjectId>, 
    wormhole_state: &WormholeState,
    pyth_state: &PythState,
    buf: vector<u8>,
    price_info_object: &mut PriceInfoObject,
    pyth_fee: Coin<SUI>,
    clock_object: &Clock,
    coin_name: String  
  ): (u256, u64) {
    let vaa = parse_and_verify(wormhole_state, buf, clock_object);
    let authorized_price_info_object_id = vec_map::get(price_info_map, &coin_name);

    assert!(authorized_price_info_object_id.value == price_info::uid_to_inner(price_info_object), ERROR_INVALID_PRICE_INFO_OBJECT_ID);

    let hot_potato_vector = update_single_price_feed(
      pyth_state,
      create_price_infos_hot_potato(pyth_state, vector::singleton(vaa), clock_object),
      price_info_object,
      pyth_fee,
      clock_object
    );

    destroy(hot_potato_vector);

    let pyth_price = pyth_get_price(pyth_state, price_info_object, clock_object);
    let pyth_price_value = pyth_price::get_price(&pyth_price);
    let pyth_price_expo = pyth_price::get_expo(&pyth_price);
    let pyth_price_timestamp = pyth_price::get_timestamp(&pyth_price);

    assert!(clock::timestamp_ms(clock_object) == pyth_price_timestamp, ERROR_INVALID_TIME);
    
    // will throw if negative
    let pyth_price_u64 = i64::get_magnitude_if_positive(&pyth_price_value);
    assert!(pyth_price_u64 != 0, ERROR_IMPOSSIBLE_PRICE);
    
    let pyth_exp_u64 = i64::get_magnitude_if_negative(&pyth_price_expo);

    let pyth_result = mul_div((pyth_price_u64 as u256), SCALAR, (pow(10, (pyth_exp_u64 as u8)) as u256));
    
    (pyth_result, pyth_price_timestamp)
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