module whirpool::itoken {
  
  use std::ascii::{String}; 

  use sui::tx_context::{Self, TxContext};
  use sui::transfer;
  use sui::object::{Self, UID};
  use sui::bag::{Self, Bag};
  use sui::balance::{Self, Supply, Balance};

  use whirpool::interest_rate_model::{Self, InterestRateModelStorage};
  use whirpool::utils::{get_coin_info};
  use whirpool::math::{fmul, fdiv, fmul_u256};


  const RESERVE_FACTOR_MANTISSA: u64 = 200000000; // 0.2e9 or 20%
  const PROTOCOL_SEIZE_SHARE_MANTISSA: u64 = 28000000; // 0.028e9 or 2.8%

  struct ITokenAdminCap has key {
    id: UID
  }

  struct Market<phantom T> has key, store {
    total_reserves: u64,
    total_reserves_shares: u64,
    total_borrows: u64,
    accrued_epoch: u64,
    borrow_index: u256,
    balance: Balance<T>,
  }

  struct ITokenStorage has key {
    id: UID,
    markets: Bag
  }

  fun init(ctx: &mut TxContext) {
    transfer::transfer(
      ITokenAdminCap {
        id: object::new(ctx)
      },
      tx_context::sender(ctx)
    );

    transfer::share_object(
      ITokenStorage {
        id: object::new(ctx),
        markets: bag::new(ctx)
      }
    );
  }

  public fun accrue<T>(
    itoken_storage: &mut ITokenStorage, 
    interest_rate_model_storage: &InterestRateModelStorage, 
    ctx: &TxContext
  ) {
    accrue_internal<T>(borrow_mut_market<T>(itoken_storage), interest_rate_model_storage, ctx);
  }

  public fun get_borrow_rate_per_epoch<T>(
    market: &Market<T>, 
    interest_rate_model_storage: &InterestRateModelStorage
    ): u64 {
    interest_rate_model::get_borrow_rate_per_epoch<T>(
      interest_rate_model_storage,
      balance::value(&market.balance),
      market.total_borrows,
      market.total_reserves
    )
  }

  fun accrue_internal<T>(
    market: &mut Market<T>, 
    interest_rate_model_storage: &InterestRateModelStorage, 
    ctx: &TxContext
  ) {
    let epochs_delta = get_epochs_delta_internal<T>(market, ctx);

    if (epochs_delta == 0) return;

    let interest_rate = epochs_delta * get_borrow_rate_per_epoch(market, interest_rate_model_storage);

    let interest_rate_amount = fmul(interest_rate, market.total_borrows);

    market.accrued_epoch = tx_context::epoch(ctx);
    market.total_borrows = interest_rate_amount +  market.total_borrows;
    market.total_reserves = fmul(interest_rate_amount, RESERVE_FACTOR_MANTISSA) + market.total_reserves;
    market.borrow_index = fmul_u256((interest_rate_amount as u256), market.borrow_index) + market.borrow_index;
  }

  fun get_epochs_delta_internal<T>(market: &Market<T>, ctx: &TxContext): u64 {
      tx_context::epoch(ctx) - market.accrued_epoch
  }

  public fun set_interest_rate_data<T>(
    _: &ITokenAdminCap,
    itoken_storage: &mut ITokenStorage, 
    interest_rate_model_storage: &mut InterestRateModelStorage,
    base_rate_per_year: u64,
    multiplier_per_year: u64,
    jump_multiplier_per_year: u64,
    kink: u64,
    ctx: &mut TxContext
  ) {
    accrue_internal<T>(borrow_mut_market<T>(itoken_storage), interest_rate_model_storage, ctx);

    interest_rate_model::set_interest_rate_data<T>(
      interest_rate_model_storage,
      base_rate_per_year,
      multiplier_per_year,
      jump_multiplier_per_year,
      kink,
      ctx
    )
  } 


  fun borrow_market<T>(itoken_storage: &ITokenStorage): &Market<T> {
    bag::borrow(&itoken_storage.markets, get_coin_info<T>())
  }

  fun borrow_mut_market<T>(itoken_storage: &mut ITokenStorage): &mut Market<T> {
    bag::borrow_mut(&mut itoken_storage.markets, get_coin_info<T>())
  }
}