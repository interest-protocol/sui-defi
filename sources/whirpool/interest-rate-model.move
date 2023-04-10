// Package that calculates the borrow or supply interest rate for a market
module interest_protocol::interest_rate_model {

  use std::ascii::{String}; 

  use sui::tx_context::{TxContext};
  use sui::transfer;
  use sui::object::{Self, UID};
  use sui::object_table::{Self, ObjectTable};
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
    interest_rate_object_table: ObjectTable<String, InterestRateData> // market_key -> Interest Rate Data
  }

  // Events

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
          interest_rate_object_table: object_table::new<String, InterestRateData>(ctx)
        }
      );
  }

  /**
  * @dev It returns the interest rate amount per millisecond given a market
  * @param storage The shared object {InterestRateModelStorage}
  * @param market_key The key to fetch the {InterestRateData} of a market
  * @param cash The current liquidity of said market
  * @param total_borrow_amount The total borrow amount of said market
  * @param reserves The total protocol reserves amount for said market
  * @return u64 The interest rate amount to charge every millisecond
  */
  public fun get_borrow_rate_per_ms(
    storage: &InterestRateModelStorage,
    market_key: String,
    cash: u64,
    total_borrow_amount: u64,
    reserves: u64
  ): u64 {
    (get_borrow_rate_per_ms_internal(storage, market_key, cash, total_borrow_amount, reserves) as u64)
  }

  /**
  * @dev It returns the interest rate amount earned by liquidity suppliers per millisecond
  * @param storage The shared object {InterestRateModelStorage}
  * @param market_key The key to fetch the {InterestRateData} of a market
  * @param cash The current liquidity of said market
  * @param total_borrow_amount The total borrow amount of said market
  * @param reserves The total protocol reserves amount for said market
  * @param reserve_factor
  * @return u64 The interest rate amount to pay liquidity suppliers every millisecond  
  */
  public fun get_supply_rate_per_ms(
    storage: &InterestRateModelStorage,
    market_key: String,
    cash: u64,
    total_borrow_amount: u64,
    reserves: u64,
    reserve_factor: u256
  ): u64 {
    let borrow_rate = d_fmul_u256((get_borrow_rate_per_ms_internal(storage, market_key, cash, total_borrow_amount, reserves) as u256), double_scalar() - reserve_factor);

    (d_fmul_u256(get_utilization_rate_internal(cash, total_borrow_amount, reserves), borrow_rate) as u64)
  }

  /**
  * @dev It holds the logic that calculates the interest rate amount per millisecond given a market
  * @param storage The shared object {InterestRateModelStorage}
  * @param market_key The key to fetch the {InterestRateData} of a market
  * @param cash The current liquidity of said market
  * @param total_borrow_amount The total borrow amount of said market
  * @param reserves The total protocol reserves amount for said market
  * @return u64 The interest rate amount to charge every millisecond
  */
  fun get_borrow_rate_per_ms_internal(
    storage: &InterestRateModelStorage,
    market_key: String,
    cash: u64,
    total_borrow_amount: u64,
    reserves: u64
    ): u64 {
      let utilization_rate = get_utilization_rate_internal(cash, total_borrow_amount, reserves);

      let data = object_table::borrow(&storage.interest_rate_object_table, market_key);

      if (data.kink >= utilization_rate) {
        (d_fmul_u256(utilization_rate, data.multiplier_per_ms) + data.base_rate_per_ms as u64)
      } else {
        let normal_rate = d_fmul_u256(data.kink, data.multiplier_per_ms) + data.base_rate_per_ms;

        let excess_utilization = utilization_rate - data.kink;
        
        (d_fmul_u256(excess_utilization, data.jump_multiplier_per_ms) + normal_rate as u64)
      }
    }

  /**
  * @dev It returns the % that a market is being based on Supply, Borrow, Reserves in 1e18 scale
  * @param cash The current liquidity of said market
  * @param total_borrow_amount The total borrow amount of said market
  * @param reserves The total protocol reserves amount for said market
  * @return u256 The utilization rate in 1e18 scale
  */
  fun get_utilization_rate_internal(cash: u64, total_borrow_amount: u64, reserves: u64): u256 {
    if (total_borrow_amount == 0) { 0 } else { 
      d_fdiv(total_borrow_amount, (cash + total_borrow_amount) - reserves)
     }
  }

  /**
  * @dev It sets the interest rate base, jump, kink and multiplier variables for Markets. Only Whirpool package can call it
  * Note that the values are per year. The function will convert them to ms via {get_ms_per_year()}
  * @param storage The shared object {InterestRateModelStorage}
  * @param base_rate_per_year The base interest rate (minimum) per year in 1e18 scale  
  * @param multiplier_pear_year The multiplier charged as more liquidity is borrowed
  * @param jump_multiplier_per_year The multiplier charged as more liquidity is borrowed after a certain utilization rate {kink}
  * @param kink The percentage that we start chargign every new borow the jump_multiplier instead of the multiplier
  */
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

    if (object_table::contains(&storage.interest_rate_object_table, key)) {
      let data = object_table::borrow_mut(&mut storage.interest_rate_object_table, key); 

      data.base_rate_per_ms = base_rate_per_ms;
      data.multiplier_per_ms = multiplier_per_ms;
      data.jump_multiplier_per_ms = jump_multiplier_per_ms;
      data.kink = kink;
    } else {
      object_table::add(
        &mut storage.interest_rate_object_table,
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

  // Test only functions
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
    let data = object_table::borrow(&storage.interest_rate_object_table, get_coin_info_string<T>());
    (data.base_rate_per_ms, data.multiplier_per_ms, data.jump_multiplier_per_ms, data.kink)
  }
}