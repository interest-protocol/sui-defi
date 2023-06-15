module oracle::ipx_oracle {

  use std::ascii::{String};
  use std::vector;
  
  use sui::clock::{Clock};
  use sui::object::{Self, UID, ID};
  use sui::vec_map::{Self, VecMap};
  use sui::tx_context::{Self, TxContext};
  use sui::event::{emit};
  use sui::math::{pow};
  use sui::coin::{Self, Coin};
  use sui::sui::{SUI};
  use sui::transfer;

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

  const SCALAR: u256 = 1000000000000000000; // 1e18
  const PRICE_MARGIN: u256 = 20000000000000000; // 0.02e18 It represents 2%

  const ERROR_IMPOSSIBLE_PRICE: u64 = 1;
  const ERROR_INVALID_ADMIN: u64 = 2;
  const ERROR_INVALID_SWITCHBOARD_FEED: u64 = 3;
  const ERROR_BAD_PRICES: u64 = 4;
  const ERROR_INVALID_PRICE_INFO_OBJECT_ID : u64 = 5;

  // Allows the admin to set authorized feeds for coins
  struct AdminCap has key {
    id: UID
  }

  // Stores the allows address for a Switchboard Fee
  // Stores the ID for a valid Pyth Price info Id
  struct AuthorizedFeed has store {
    switchboard: address,
    pyth_network: ID
  }

  // Storage for this module
  struct OracleStorage has key {
     id: UID,
     authorized_feeds: VecMap<String, AuthorizedFeed>
  }

  // Events

  struct NewAdmin has drop, copy {
    admin: address
  }

  struct NewFeed has drop, copy {
    switchboard_feed: address,
    pyth_price_info_id: ID,
    coin_name: String
  }

  struct GetPrice has copy, drop {
    sender: address,
    switchboard_result: u256,
    switchboard_timestamp: u64,
    pyth_timestamp: u64,
    pyth_result: u256,
    pyth_fee_value: u64,
    coin_name: String
  }

  // Hot Potato to be passed. IMPORTANT DO NOT ADD ABILITIES
  // A Consumer contract needs to destroy it with read_price and assert the coin_name 
  struct Price {
    switchboard_result: u256,
    pyth_result: u256,
    scalar: u256,
    pyth_timestamp: u64,
    switchboard_timestamp: u64,
    average: u256, // average between pyth and switchboard prices
    coin_name: String
  }

  /**
  * ctx: The transaction context
  */
  fun init(ctx: &mut TxContext) {
    // Give the admin cap to the deployer
    transfer::transfer(
      AdminCap {
        id: object::new(ctx)
      },
      tx_context::sender(ctx)
    );

    // Set up the initial state and share it
    // This object contains maps from CoinName => authorized feeds
    transfer::share_object(
      OracleStorage {
        id: object::new(ctx),
        authorized_feeds: vec_map::empty()
      }
    );
  }

  /**
  * @notice This function creates a hot potato with the latest prices from Pyth and Switchboard.
  * @dev The pyth network logic and parameters are from https://docs.pyth.network/pythnet-price-feeds/sui.
  * @storage This contract storage
  * @wormhole_state The state of the Wormhole module on Sui
  * @pyth_state The state of the Pyth module on Sui
  * @buf Price attestations in bytes
  * @price_info_object An object that contains price information. One per asset
  * @pyth_fee There is a cost to request a price update from Pyth
  * @clock_object The shared Clock object from Sui
  * @switchboard_feed A price aggregator object from Switchboard
  * @return Price Hot Potato to be consumed
  */
  public fun get_price(
    storage: &mut OracleStorage, 
    wormhole_state: &WormholeState,
    pyth_state: &PythState,
    buf: vector<u8>,
    price_info_object: &mut PriceInfoObject,
    pyth_fee: Coin<SUI>,
    clock_object: &Clock,
    switchboard_feed: &Aggregator, 
    coin_name: String,
    ctx: &mut TxContext
  ): Price {
    
    // Save the value of the pyth fee to pass to the event
    let pyth_fee_value = coin::value(&pyth_fee);
    
    // Calculate the price from switchboard on a scalar of 1e18. One dollar is 1e18
    let (switchboard_result, switchboard_timestamp) = get_switchboard_data(&storage.authorized_feeds, switchboard_feed, coin_name);

    // Calculate the price from Pyth Network on a scalar of 1e18. One dollar is 1e18
    let (pyth_result, pyth_timestamp) = get_pyth_network_data(
      &storage.authorized_feeds,
      wormhole_state,pyth_state,
      buf,
      price_info_object,
      pyth_fee,
      clock_object,
      coin_name
    );

    // Get the average between both oracles with a guard of 2% divergence
    let average = get_safe_average(switchboard_result, pyth_result);

    // A price of 0 USD is impossible
    assert!(average != 0, ERROR_IMPOSSIBLE_PRICE);

    // Emit the event
    emit(GetPrice { sender: tx_context::sender(ctx), switchboard_result, switchboard_timestamp, pyth_result, pyth_timestamp, pyth_fee_value, coin_name });

    // Create the Hot Potato
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

  /**
  * @notice This function destroys the Price hot potato to be consumed. The consumer must assert that the coin_name is correct
  * @return (switchboard_result, pyth_result, scalar, average, pyth_timestamp, switchboard_timestamp, coin_name)
  */
  public fun read_price(price: Price): (u256, u256, u256, u256, u64, u64, String) {
    let Price { switchboard_result, pyth_result, scalar, pyth_timestamp, switchboard_timestamp, average, coin_name } = price;
    (average, switchboard_result, pyth_result, scalar, pyth_timestamp, switchboard_timestamp, coin_name)
  }

  /**
  * @notice It allows the admin to set an authorized feed for both pyth and switchboard
  * @_ The admin cap to guard this function
  * @storage This contract storage
  * switchboard_aggregator The Switchboard Aggregator address that will be associated with T
  * price_info_object The Pyth Network Price Info Object Id that will be associated with T
  */
  entry fun set_feed<T>(
    _:& AdminCap, 
    storage: &mut OracleStorage, 
    switchboard_aggregator: &Aggregator,
    price_info_object: &PriceInfoObject
  ) {
    // Save the T name in string locally
    let coin_name = get_struct_name_string<T>();
    // Get the Id of the Pyth Network Price Info Object
    let pyth_price_info_id = price_info::uid_to_inner(price_info_object);
    // Get the address of the Switchboard Aggregator
    let aggregator_address = aggregator::aggregator_address(switchboard_aggregator);

    // We need to create a new Value if it does not exist
    if (vec_map::contains(&storage.authorized_feeds, &coin_name)) {
      // If the Value already exists, we get it and mutate it
      let authorized_feed = vec_map::get_mut(&mut storage.authorized_feeds, &coin_name);
      authorized_feed.switchboard = aggregator_address;
      authorized_feed.pyth_network = pyth_price_info_id;
    } else {
      // If it already exists, we just update it
      vec_map::insert(
        &mut storage.authorized_feeds, 
        coin_name, 
        AuthorizedFeed { switchboard: aggregator_address, pyth_network: pyth_price_info_id }
      );
    };

    // Emit the event
    emit(NewFeed {
      switchboard_feed: aggregator_address,
      pyth_price_info_id,
      coin_name
    });
  }

  /**
  * @notice We fetch the price from Switchboard and parse it to a uint256 with a scalar of 1e18. 
  * @feed_map A map coin_name => authorized aggregator address
  * @switchboard_feed A Switchboard price aggregator
  * @coin_name The string repreation of a T
  * @return (price, timestamp)
  */
  fun get_switchboard_data(
    feed_map: &VecMap<String, AuthorizedFeed>,
    switchboard_feed: &Aggregator,
    coin_name: String
  ): (u256, u64) {
    
    // Save the authorized feed address locally
    let authorized_feed = vec_map::get(feed_map, &coin_name);

    // Ensure that the switchboard_feed is authorized for coin_name
    assert!(authorized_feed.switchboard == aggregator::aggregator_address(switchboard_feed), ERROR_INVALID_SWITCHBOARD_FEED);

    // The logic was based on https://github.com/switchboard-xyz/sbv2-sui/tree/main/move/testnet/switchboard_std
    // First get the values
    let (switchboard_result, switchboard_timestamp) = aggregator::latest_value(switchboard_feed);
    // We need to get the raw value, scaling factor and if the price is positive or negative
    let (switchboard_value, switchboard_scaling_factor, neg) = math::unpack(switchboard_result);

    // We need to make sure that the price is positive and not equal to zero
    assert!(switchboard_value != 0 && !neg, ERROR_IMPOSSIBLE_PRICE);

    // We rescale the raw value to 1e18
    (mul_div((switchboard_value as u256), SCALAR, (pow(10, switchboard_scaling_factor) as u256)), switchboard_timestamp)
  }

  /**
  * @notice We update the Pyth Network Price Feed and then fetch it
  * @dev All logic can be found https://docs.pyth.network/pythnet-price-feeds/sui
  * @feed_map: A map coin_name => authorized price info object ID
  * @wormhole_state The state of the Wormhole module on Sui
  * @pyth_state The state of the Pyth module on Sui
  * @buf Price attestations in bytes
  * @price_info_object An object that contains price information. One per asset
  * @pyth_fee There is a cost to request a price update from Pyth
  * @clock_object The shared Clock object from Sui
  * @coin_name The string repreation of a T
  * @return (price, timestamp)
  */
  fun get_pyth_network_data(
    feed_map: &VecMap<String, AuthorizedFeed>,
    wormhole_state: &WormholeState,
    pyth_state: &PythState,
    buf: vector<u8>,
    price_info_object: &mut PriceInfoObject,
    pyth_fee: Coin<SUI>,
    clock_object: &Clock,
    coin_name: String  
  ): (u256, u64) {

    // Save the authorized feed address locally
    let authorized_feed = vec_map::get(feed_map, &coin_name);

    // We need to make sure this price info object is authorized for type T (coin_name)
    assert!(authorized_feed.pyth_network == price_info::uid_to_inner(price_info_object), ERROR_INVALID_PRICE_INFO_OBJECT_ID);
    
    // Make sure the the attestations are real
    let vaa = parse_and_verify(wormhole_state, buf, clock_object);

    // Update the Pyth Network Price Feeds
    let hot_potato_vector = update_single_price_feed(
      pyth_state,
      create_price_infos_hot_potato(pyth_state, vector::singleton(vaa), clock_object),
      price_info_object,
      pyth_fee,
      clock_object
    );

    // Destroy the Hot Potato
    destroy(hot_potato_vector);

    // Get the price raw value, exponent and timestamp
    let pyth_price = pyth_get_price(pyth_state, price_info_object, clock_object);
    let pyth_price_value = pyth_price::get_price(&pyth_price);
    let pyth_price_expo = pyth_price::get_expo(&pyth_price);
    let pyth_price_timestamp = pyth_price::get_timestamp(&pyth_price);
    
    // if the price is negative it will throw
    let pyth_price_u64 = i64::get_magnitude_if_positive(&pyth_price_value);
    // We do not accept a price of 0
    assert!(pyth_price_u64 != 0, ERROR_IMPOSSIBLE_PRICE);

    let is_exponent_negative = i64::get_is_negative(&pyth_price_expo);
    
    // Get the exponent raw value
    let pyth_exp_u64 = if (is_exponent_negative) { i64::get_magnitude_if_negative(&pyth_price_expo) } else { i64::get_magnitude_if_positive(&pyth_price_expo) };

    // The goal is to scale the raw value to 1e18 scalar
    // if the exponent is negative we first scale it up by 1e18 then divide by the pow(10, exponent), to remove the extra decimals
    let pyth_result = if (is_exponent_negative) 
    { mul_div((pyth_price_u64 as u256), SCALAR, (pow(10, (pyth_exp_u64 as u8)) as u256)) } 
    else 
    // If the exponent is positive, we need to substract the decimal houses from 18 and then scale it up. 
    { (pyth_price_u64 as u256)  * (pow(10, 18 - (pyth_exp_u64 as u8)) as u256) };
    
    (pyth_result, pyth_price_timestamp)
  }

  /**
  * @notice it calculates the average between x and y. It makes sures that there is a diff of 2% or it will throw
  */
  public fun get_safe_average(x: u256, y:u256): u256 {
    // If they are equal we do not need to do anything
    if (x == y) return x;

    // If x is larger than y
    if (x > y) {
      // calculate the difference
      let diff = x - y;
      // assert is within the allowed difference
      assert!(PRICE_MARGIN >= (diff * SCALAR) / x, ERROR_BAD_PRICES);
    }; 

    // if y is larger than x
    if (y > x) {
      // Take the difference
      let diff = y - x;
      // Assert that is within the parameters
      assert!(PRICE_MARGIN >= (diff * SCALAR) / y, ERROR_BAD_PRICES);
    };

    average(x, y) 
  }

  /**
  * @notice It transfers the admin cap to a new recipient. It CANNOT be the address zero
  * @param cap The AdminCap
  * @recipient The new admin
  */
  entry fun transfer_admin_cap(cap: AdminCap, recipient: address) {
    assert!(recipient != @0x0, ERROR_INVALID_ADMIN);
    transfer::transfer(cap, recipient);
    emit(NewAdmin { admin: recipient });
  }

  // Test functions

  #[test_only]
  public fun init_for_testing(ctx: &mut TxContext) {
    init(ctx)
  }

  #[test_only]
  public fun get_price_for_testing<T>(
    switchboard_result: u256,
    switchboard_timestamp: u64,
    pyth_result: u256,
    pyth_timestamp: u64,
    average: u256,
  ): Price {
    Price {
      switchboard_result,
      switchboard_timestamp,
      pyth_timestamp,
      pyth_result,
      average,
      scalar: SCALAR,
      coin_name: get_struct_name_string<T>()
    }
  }
}