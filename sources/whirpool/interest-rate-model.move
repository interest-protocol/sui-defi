module interest_protocol::interest_rate_model {

  use std::ascii::{String}; 

  use sui::tx_context::{TxContext};
  use sui::transfer;
  use sui::object::{Self, UID};
  use sui::table::{Self, Table};
  use sui::event;

  use interest_protocol::math::{fmul, fdiv, one};
  use interest_protocol::utils::{get_coin_info};

  friend interest_protocol::whirpool;

  // TODO: need to update to timestamps whenever they are implemented in the devnet
  const EPOCHS_PER_YEAR: u64 = 3504; // 24 / 2.5 * 365

  struct InterestRateData has key, store {
    id: UID,
    base_rate_per_epoch: u64,
    multiplier_per_epoch: u64,
    jump_multiplier_per_epoch: u64,
    kink: u64
  }

  struct InterestRateModelStorage has key {
    id: UID,
    interest_rate_table: Table<String, InterestRateData>
  }

  struct NewInterestRateData<phantom T> has copy, drop {
    base_rate_per_epoch: u64,
    multiplier_per_epoch: u64,
    jump_multiplier_per_epoch: u64,
    kink: u64
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
  ): u64 {
    get_borrow_rate_per_epoch_internal(storage, market_key, cash, total_borrow_amount, reserves)
  }

  public fun get_supply_rate_per_epoch(
    storage: &InterestRateModelStorage,
    market_key: String,
    cash: u64,
    total_borrow_amount: u64,
    reserves: u64,
    reserve_factor: u64
  ): u64 {
    let borrow_rate = fmul(get_borrow_rate_per_epoch_internal(storage, market_key, cash, total_borrow_amount, reserves), (one() as u64) - reserve_factor);

    fmul(get_utilization_rate_internal(cash, total_borrow_amount, reserves), borrow_rate)
  }

  fun get_borrow_rate_per_epoch_internal(
    storage: &InterestRateModelStorage,
    market_key: String,
    cash: u64,
    total_borrow_amount: u64,
    reserves: u64
    ): u64 {
      let utilization_rate = get_utilization_rate_internal(cash, total_borrow_amount, reserves);

      let data = table::borrow(&storage.interest_rate_table, market_key);

      if (data.kink >= utilization_rate) {
        fmul(utilization_rate, data.multiplier_per_epoch) + data.base_rate_per_epoch
      } else {
        let normal_rate = fmul(data.kink, data.multiplier_per_epoch) + data.base_rate_per_epoch;

        let excess_utilization = utilization_rate - data.kink;
        
        fmul(excess_utilization, data.jump_multiplier_per_epoch) + normal_rate
      }
    }

  fun get_utilization_rate_internal(cash: u64, total_borrow_amount: u64, reserves: u64): u64 {
    if (total_borrow_amount == 0) { 0 } else { 
      fdiv(total_borrow_amount, (cash + total_borrow_amount) - reserves)
     }
  }

  public(friend) fun set_interest_rate_data<T>(
    storage: &mut InterestRateModelStorage,
    base_rate_per_year: u64,
    multiplier_per_year: u64,
    jump_multiplier_per_year: u64,
    kink: u64,
    ctx: &mut TxContext
  ) {
    let key = get_coin_info<T>();

    let base_rate_per_epoch = base_rate_per_year / EPOCHS_PER_YEAR;
    let multiplier_per_epoch = multiplier_per_year / EPOCHS_PER_YEAR;
    let jump_multiplier_per_epoch = jump_multiplier_per_year / EPOCHS_PER_YEAR;

    if (table::contains(&storage.interest_rate_table, key)) {
      let data = table::borrow_mut(&mut storage.interest_rate_table, key); 

      data.base_rate_per_epoch = base_rate_per_epoch;
      data.multiplier_per_epoch = multiplier_per_epoch;
      data.jump_multiplier_per_epoch = jump_multiplier_per_epoch;
      data.kink = kink;
    } else {
      table::add(
        &mut storage.interest_rate_table,
        key,
        InterestRateData {
          id: object::new(ctx),
          base_rate_per_epoch,
          multiplier_per_epoch,
          jump_multiplier_per_epoch,
          kink
        }
      );
    };

    event::emit(
      NewInterestRateData<T> {
      base_rate_per_epoch,
      multiplier_per_epoch,
      jump_multiplier_per_epoch,
      kink
      }
    );
  }
}