module whirpool::itoken {
  
  use std::ascii::{String}; 

  use sui::tx_context::{Self, TxContext};
  use sui::transfer;
  use sui::object::{Self, UID};
  use sui::bag::{Self, Bag};
  use sui::balance::{Self, Supply, Balance};
  use sui::coin::{Self, Coin};

  use whirpool::controller::{deposit_allowed};
  use whirpool::interest_rate_model::{Self, InterestRateModelStorage};
  use whirpool::utils::{get_coin_info};
  use whirpool::math::{fmul, fdiv, fmul_u256};


  const RESERVE_FACTOR_MANTISSA: u64 = 200000000; // 0.2e9 or 20%
  const PROTOCOL_SEIZE_SHARE_MANTISSA: u64 = 28000000; // 0.028e9 or 2.8%
  const INITIAL_EXCHANGE_RATE_MANTISSA: u64 = 2000000000; // 1e11

  const ERROR_DEPOSIT_NOT_ALLOWED: u64 = 1;

  struct ITokenAdminCap has key {
    id: UID
  }

  struct IToken<phantom T> has drop {}

  struct Market<phantom T> has key, store {
    id: UID,
    total_reserves: u64,
    total_reserves_shares: u64,
    total_borrows: u64,
    accrued_epoch: u64,
    borrow_index: u256,
    balance: Balance<T>,
    asset_off_set: u32,
    supply: Supply<IToken<T>>
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

  public fun deposit<T>(
    itoken_storage: &mut ITokenStorage, 
    interest_rate_model_storage: &mut InterestRateModelStorage,
    asset: Coin<T>,
    ctx: &mut TxContext
  ): Coin<IToken<T>> {
      let market = borrow_mut_market<T>(itoken_storage);

      accrue_internal<T>(market, interest_rate_model_storage, ctx);

      assert!(!deposit_allowed<T>(), ERROR_DEPOSIT_NOT_ALLOWED);

      let coin_value = coin::value(&asset);

      let shares = fdiv(coin_value, get_current_exchange_rate<T>(market));

      balance::join(&mut market.balance, coin::into_balance(asset));

      coin::from_balance(balance::increase_supply(&mut market.supply, shares), ctx)
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

  public fun create_market<T>(
    _: &ITokenAdminCap, 
    itoken_storage: &mut ITokenStorage, 
    ctx: &mut TxContext
    ) {
    bag::add(
      &mut itoken_storage.markets, 
      get_coin_info<T>(),
      Market {
      id: object::new(ctx),
      total_reserves: 0,
      total_reserves_shares: 0,
      total_borrows: 0,
      accrued_epoch: tx_context::epoch(ctx),
      borrow_index: 0,
      balance: balance::zero<T>(),
      asset_off_set: 0,
      supply: balance::create_supply(IToken<T> {})
    });
  }

  fun get_current_exchange_rate<T>(market: &Market<T>): u64 {
    let supply_value = balance::supply_value(&market.supply);
      if (supply_value == 0) {
        INITIAL_EXCHANGE_RATE_MANTISSA
      } else {
        let cash = balance::value(&market.balance);
        fmul(cash + market.total_borrows - market.total_reserves, supply_value)
      }
  }

  fun borrow_market<T>(itoken_storage: &ITokenStorage): &Market<T> {
    bag::borrow(&itoken_storage.markets, get_coin_info<T>())
  }

  fun borrow_mut_market<T>(itoken_storage: &mut ITokenStorage): &mut Market<T> {
    bag::borrow_mut(&mut itoken_storage.markets, get_coin_info<T>())
  }
}