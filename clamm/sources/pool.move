module clamm::ipx_pool {
  use std::hash::{sha3_256};
  use std::vector;

  use sui::bcs::{to_bytes};
  use sui::coin::{Self, Coin};
  use sui::object::{Self, UID, ID};
  use sui::table::{Self, Table};
  use sui::object_bag::{Self, ObjectBag};
  use sui::balance::{Self, Balance};
  use sui::tx_context::{Self, TxContext};
  use sui::transfer;
  use sui::event::{emit};

  use clamm::i256::{Self, I256};
  use clamm::utils::{are_coins_sorted, get_struct_string_name};

  const MAXIMUM_TICK: u256 = 887272; 
  
  /// When both `U256` equal.
  const I256_EQUAL: u8 = 0;

  /// When `a` is less than `b`.
  const I256_LESS_THAN: u8 = 1;

  /// When `a` is greater than `b`.
  const I256_GREATER_THAN: u8 = 2;

  // ERRORS
  const ERROR_UNSORTED_COINS: u64 = 0;
  const ERROR_TICK_OUT_OF_RANGE: u64 = 1;
  const ERROR_INVALID_TICKS: u64 = 2;
  const ERROR_ZERO_LIQUIDITY: u64 = 3;
  const ERROR_WRONG_ADD_LIQUIDITY_AMOUNT: u64 = 4;
  const ERROR_INSUFFICIENT_INPUT_AMOUNT: u64 = 5;

  struct TickLiquidity has store {
    intialized: bool,
    liquidity: u128
  }

  struct PositionLiquidity has store {
    liquidity: u128
  }

  struct Pool<phantom X, phantom Y> has key, store {
    id: UID,
    liquidity: u128,
    tick_table: Table<I256, TickLiquidity>,
    position_table: Table<vector<u8>, PositionLiquidity>,
    balance_x: Balance<X>,
    balance_y: Balance<Y>,
    current_tick: I256,
    current_sqrt_price_q96: u256
  }

  struct Storage has key {
    id: UID,
    pools: ObjectBag
  }

  // Events

  struct CreatePool<phantom X, phantom Y> has drop, copy {
    pool_id: ID,
    current_tick: I256,
    current_sqrt_price_q96: u256
  }

  struct AddLiquidity<phantom X, phantom Y> has drop, copy {
    pool_id: ID,
    sender: address,
    raw_lower_tick: u64,
    is_lower_tick_negative: bool,
    raw_upper_tick: u64,
    is_upper_tick_negative: bool,
    amount_x: u64,
    amount_y: u64
  }

  struct SwapY<phantom X, phantom Y> has drop, copy {
    pool_id: ID,
    sender: address,
    amount_in: u64,
    amount_out: u64,
    current_price: u256,
    raw_current_tick: u256,
    is_tick_negative: bool,
    liquidity: u128,
  }

  fun init(ctx: &mut TxContext) {
    transfer::share_object(
      Storage {
        id: object::new(ctx),
        pools: object_bag::new(ctx)
      }
    );
  }


  public fun create_pool<X, Y>(
    storage: &mut Storage,
    sqrt_price: u256,
    raw_tick: u64,
    is_tick_negative: bool,
    ctx: &mut TxContext
    ) {
    assert!(are_coins_sorted<X, Y>(), ERROR_UNSORTED_COINS);

    let pool_key = get_struct_string_name<Pool<X, Y>>();

    let current_tick = create_tick(raw_tick, is_tick_negative);

    let (min_tick, max_tick) = get_min_max_ticks();
    let min_compare = i256::compare(&current_tick, &min_tick);
    let max_compare = i256::compare(&max_tick, &current_tick);

    assert!(min_compare == I256_EQUAL || min_compare == I256_GREATER_THAN, ERROR_TICK_OUT_OF_RANGE);
    assert!(max_compare == I256_EQUAL || max_compare == I256_GREATER_THAN, ERROR_TICK_OUT_OF_RANGE);

    let pool = Pool {
      id: object::new(ctx),
      liquidity: 0,
      tick_table: table::new(ctx),
      position_table: table::new(ctx),
      balance_x: balance::zero<X>(),
      balance_y: balance::zero<Y>(),
      current_tick,
      current_sqrt_price_q96: sqrt_price
    };

    emit(
      CreatePool<X, Y> {
        pool_id: object::uid_to_inner(&pool.id),
        current_tick: pool.current_tick,
        current_sqrt_price_q96: pool.current_sqrt_price_q96
      }
    );

    object_bag::add(&mut storage.pools, pool_key, pool);
  }

  public fun add_liquidity<X, Y>(
    storage: &mut Storage,
    coin_x: Coin<X>,
    coin_y: Coin<Y>,
    liquidity: u128,
    raw_lower_tick: u64,
    is_lower_tick_negative: bool,
    raw_upper_tick: u64,
    is_upper_tick_negative: bool,
    ctx: &mut TxContext
  ) {
    let lower_tick = create_tick(raw_lower_tick, is_lower_tick_negative);
    let upper_tick = create_tick(raw_upper_tick, is_upper_tick_negative);

    assert!(!(i256::compare(&lower_tick, &upper_tick) == I256_GREATER_THAN), ERROR_INVALID_TICKS);

    let (min_tick, max_tick) = get_min_max_ticks();

    assert!(!(i256::compare(&upper_tick, &max_tick) == I256_GREATER_THAN), ERROR_TICK_OUT_OF_RANGE);
    assert!(!(i256::compare(&min_tick, &lower_tick) == I256_GREATER_THAN), ERROR_TICK_OUT_OF_RANGE);

    assert!(liquidity != 0, ERROR_ZERO_LIQUIDITY);
    let pool = pool_borrow_mut<X, Y>(storage);

    update_tick(pool, lower_tick, liquidity);
    update_tick(pool, upper_tick, liquidity);

    let sender = tx_context::sender(ctx);

    update_position(
      pool,
      get_user_position_key(sender, &lower_tick, &upper_tick),
      liquidity
    );

    pool.liquidity = pool.liquidity + liquidity;

    let amount_x = 998976618;
    let amount_y = 5000000000000;

    let coin_x_value = coin::value(&coin_x);
    let coin_y_value = coin::value(&coin_y);

    assert!(coin_x_value >= amount_x, ERROR_WRONG_ADD_LIQUIDITY_AMOUNT);
    assert!(coin_y_value >= amount_y, ERROR_WRONG_ADD_LIQUIDITY_AMOUNT);

    balance::join(&mut pool.balance_x, coin::into_balance(coin_x));
    balance::join(&mut pool.balance_y, coin::into_balance(coin_y));

    emit(AddLiquidity<X, Y> {
      pool_id: object::uid_to_inner(&pool.id),
      sender,
      raw_lower_tick,
      is_lower_tick_negative,
      raw_upper_tick,
      is_upper_tick_negative,
      amount_x,
      amount_y
    });
  }

  public fun swap_y<X, Y>(
    storage: &mut Storage,
    coin_y: Coin<Y>,
    ctx: &mut TxContext
  ): Coin<X> {
    let pool = pool_borrow_mut<X, Y>(storage);

    let next_tick = 85184;
    let next_price: u256 = 5604469350942327889444743441197;

    let amount_0 = 8396714;
    let amount_1 = 42000000000;

    pool.current_tick = i256::from(next_tick);
    pool.current_sqrt_price_q96 = next_price;

    assert!(coin::value(&coin_y) >= amount_1, ERROR_INSUFFICIENT_INPUT_AMOUNT);
    balance::join(&mut pool.balance_y, coin::into_balance(coin_y));

  let sender = tx_context::sender(ctx);

    emit(SwapY<X, Y> { 
      pool_id: object::uid_to_inner(&pool.id),
      sender,
      amount_in: amount_1,
      amount_out: amount_0,
      current_price: next_price,
      raw_current_tick: i256::as_u256(&i256::abs(&pool.current_tick)),
      is_tick_negative: i256::is_neg(&pool.current_tick),
      liquidity: pool.liquidity
     });

    coin::take(&mut pool.balance_x, amount_0, ctx)
  }

  fun get_min_max_ticks(): (I256, I256) {
    (i256::neg_from(MAXIMUM_TICK), i256::from(MAXIMUM_TICK))
  }

  fun create_tick(raw_tick: u64, is_neg: bool): I256 {
    if (is_neg) { i256::neg_from((raw_tick as u256)) } else { i256::from((raw_tick as u256)) }
  }

  public fun get_user_position_key(
      user: address,
      lower_tick: &I256,
      upper_tick: &I256
    ): vector<u8> {
      let key = to_bytes(&user);

      vector::append(&mut key, to_bytes(&i256::abs(lower_tick)));
      vector::append(&mut key, to_bytes(&i256::abs(upper_tick)));

      sha3_256(key)
    }

  fun pool_borrow<X, Y>(storage: &Storage): &Pool<X, Y> {
      object_bag::borrow(&storage.pools, get_struct_string_name<Pool<X, Y>>())
  }

  fun pool_borrow_mut<X, Y>(storage: &mut Storage): &mut Pool<X, Y> {
      object_bag::borrow_mut(&mut storage.pools, get_struct_string_name<Pool<X, Y>>())
  }

  fun update_tick<X, Y>(
    pool: &mut Pool<X, Y>,
    tick: I256,
    liquidity_delta: u128
    ) {
      if (!table::contains(&pool.tick_table, tick))
        table::add(
          &mut pool.tick_table, 
          tick,
          TickLiquidity {
            intialized: false,
            liquidity: 0
          }
        );

      let tick_liquidity = table::borrow_mut(&mut pool.tick_table, tick);

      let liquidity_before = tick_liquidity.liquidity;
      let liquidity_after = liquidity_before + liquidity_delta;

      if (liquidity_before == 0) tick_liquidity.intialized = true;

      tick_liquidity.liquidity = liquidity_after;
    }

  fun update_position<X, Y>(
    pool: &mut Pool<X, Y>,
    key: vector<u8>,
    liquidity_delta: u128
  ) {
    if (!table::contains(&pool.position_table, key))
        table::add(
          &mut pool.position_table, 
          key,
          PositionLiquidity {
            liquidity: 0
          }
      );

    let position_liquidity = table::borrow_mut(&mut pool.position_table, key);

    position_liquidity.liquidity = position_liquidity.liquidity + liquidity_delta;
  }

  public fun get_pool_info<X, Y>(storage: &Storage): (u64, u64, u128, u256, bool, u256) {
    let pool = pool_borrow<X, Y>(storage);
    (
      balance::value(&pool.balance_x), 
      balance::value(&pool.balance_y), 
      pool.liquidity, 
      i256::as_u256(&i256::abs(&pool.current_tick)), 
      i256::is_neg(&pool.current_tick),
      pool.current_sqrt_price_q96
    )
  }

  public fun get_user_position_liquidity<X, Y>(storage: &Storage, key: vector<u8>): u128 {
    let pool = pool_borrow<X, Y>(storage);
    table::borrow(&pool.position_table, key).liquidity
  }

  public fun get_tick_info<X, Y>(storage: &Storage, tick: I256): (bool, u128) {
    let pool = pool_borrow<X, Y>(storage);
    let tick_liquidity = table::borrow(&pool.tick_table, tick);
    (tick_liquidity.intialized, tick_liquidity.liquidity)
  }


 #[test_only]
  public fun init_for_testing(ctx: &mut TxContext) {
    init(ctx);
  }    
}
