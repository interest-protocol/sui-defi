module interest_protocol::interest_rate_model {

  use std::ascii::{String}; 

  use sui::tx_context::{TxContext};
  use sui::transfer;
  use sui::object::{Self, UID};
  use sui::table::{Self, Table};
  use sui::event;

  use interest_protocol::math::{d_fdiv, d_fmul_u256, double_scalar};
  use interest_protocol::utils::{get_coin_info_string, get_ms_per_year};

  friend interest_protocol::whirpool;

  struct InterestRateData has key, store {
    id: UID,
    base_rate_per_ms: u256,
    multiplier_per_ms: u256,
    jump_multiplier_per_ms: u256,
    kink: u256
  }

  struct InterestRateModelStorage has key {
    id: UID,
    interest_rate_table: Table<String, InterestRateData>
  }

  struct NewInterestRateData<phantom T> has copy, drop {
    base_rate_per_ms: u256,
    multiplier_per_ms: u256,
    jump_multiplier_per_ms: u256,
    kink: u256
  }

  fun init(ctx: &mut TxContext) {
      transfer::share_object(
        InterestRateModelStorage {
          id: object::new(ctx),
          interest_rate_table: table::new<String, InterestRateData>(ctx)
        }
      );
  }

  public fun get_borrow_rate_per_epoch(
    storage: &InterestRateModelStorage,
    market_key: String,
    cash: u64,
    total_borrow_amount: u64,
    reserves: u64
  ): u256 {
    get_borrow_rate_per_ms_internal(storage, market_key, cash, total_borrow_amount, reserves)
  }

  public fun get_supply_rate_per_epoch(
    storage: &InterestRateModelStorage,
    market_key: String,
    cash: u64,
    total_borrow_amount: u64,
    reserves: u64,
    reserve_factor: u256
  ): u256 {
    let borrow_rate = d_fmul_u256(get_borrow_rate_per_ms_internal(storage, market_key, cash, total_borrow_amount, reserves), double_scalar() - reserve_factor);

    d_fmul_u256(get_utilization_rate_internal(cash, total_borrow_amount, reserves), borrow_rate)
  }

  fun get_borrow_rate_per_ms_internal(
    storage: &InterestRateModelStorage,
    market_key: String,
    cash: u64,
    total_borrow_amount: u64,
    reserves: u64
    ): u256 {
      let utilization_rate = get_utilization_rate_internal(cash, total_borrow_amount, reserves);

      let data = table::borrow(&storage.interest_rate_table, market_key);

      if (data.kink >= utilization_rate) {
        d_fmul_u256(utilization_rate, data.multiplier_per_ms) + data.base_rate_per_ms
      } else {
        let normal_rate = d_fmul_u256(data.kink, data.multiplier_per_ms) + data.base_rate_per_ms;

        let excess_utilization = utilization_rate - data.kink;
        
        d_fmul_u256(excess_utilization, data.jump_multiplier_per_ms) + normal_rate
      }
    }

  fun get_utilization_rate_internal(cash: u64, total_borrow_amount: u64, reserves: u64): u256 {
    if (total_borrow_amount == 0) { 0 } else { 
      d_fdiv(total_borrow_amount, (cash + total_borrow_amount) - reserves)
     }
  }

  public(friend) fun set_interest_rate_data<T>(
    storage: &mut InterestRateModelStorage,
    base_rate_per_year: u256,
    multiplier_per_year: u256,
    jump_multiplier_per_year: u256,
    kink: u256,
    ctx: &mut TxContext
  ) {
    let key = get_coin_info_string<T>();

    let ms_per_year = (get_ms_per_year() as u256);

    let base_rate_per_ms = base_rate_per_year / ms_per_year;
    let multiplier_per_ms = multiplier_per_year / ms_per_year;
    let jump_multiplier_per_ms = jump_multiplier_per_year / ms_per_year;

    if (table::contains(&storage.interest_rate_table, key)) {
      let data = table::borrow_mut(&mut storage.interest_rate_table, key); 

      data.base_rate_per_ms = base_rate_per_ms;
      data.multiplier_per_ms = multiplier_per_ms;
      data.jump_multiplier_per_ms = jump_multiplier_per_ms;
      data.kink = kink;
    } else {
      table::add(
        &mut storage.interest_rate_table,
        key,
        InterestRateData {
          id: object::new(ctx),
          base_rate_per_ms,
          multiplier_per_ms,
          jump_multiplier_per_ms,
          kink
        }
      );
    };

    event::emit(
      NewInterestRateData<T> {
      base_rate_per_ms,
      multiplier_per_ms,
      jump_multiplier_per_ms,
      kink
      }
    );
  }

  #[test_only]
  public fun init_for_testing(ctx: &mut TxContext) {
    init(ctx);
  }

  #[test_only]
  public fun set_interest_rate_data_test<T>(
    storage: &mut InterestRateModelStorage,
    base_rate_per_year: u256,
    multiplier_per_year: u256,
    jump_multiplier_per_year: u256,
    kink: u256,
    ctx: &mut TxContext
  ) {
    set_interest_rate_data<T>(storage, base_rate_per_year, multiplier_per_year, jump_multiplier_per_year, kink, ctx);
  }

  #[test_only]
  public fun get_interest_rate_data<T>(storage: &InterestRateModelStorage): (u256, u256, u256, u256) {
    let data = table::borrow(&storage.interest_rate_table, get_coin_info_string<T>());
    (data.base_rate_per_ms, data.multiplier_per_ms, data.jump_multiplier_per_ms, data.kink)
  }
}