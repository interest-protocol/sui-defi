module whirpool::itoken {
  use std::ascii::{String};
  use std::vector;
  
  use sui::tx_context::{Self, TxContext};
  use sui::transfer;
  use sui::object::{Self, UID};
  use sui::bag::{Self, Bag};
  use sui::balance::{Self, Supply, Balance};
  use sui::coin::{Self, Coin};
  use sui::pay;

  use whirpool::interest_rate_model::{Self, InterestRateModelStorage};
  use whirpool::utils::{get_coin_info};
  use whirpool::math::{fmul, fdiv, fmul_u256};

  const RESERVE_FACTOR_MANTISSA: u64 = 200000000; // 0.2e9 or 20%
  const PROTOCOL_SEIZE_SHARE_MANTISSA: u64 = 28000000; // 0.028e9 or 2.8%
  const INITIAL_EXCHANGE_RATE_MANTISSA: u64 = 2000000000; // 1e11

  const ERROR_DEPOSIT_NOT_ALLOWED: u64 = 1;
  const ERROR_WITHDRAW_NOT_ALLOWED: u64 = 2;
  const ERROR_NOT_ENOUGH_CASH_TO_WITHDRAW: u64 = 3;
  const ERROR_NOT_ENOUGH_CASH_TO_LEND: u64 = 4;
  const ERROR_BORROW_NOT_ALLOWED: u64 = 5;
  const ERROR_REPAY_NOT_ALLOWED: u64 = 6;
  const ERROR_MARKET_IS_PAUSED: u64 = 7;

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
    supply: Supply<IToken<T>>,
    is_paused: bool,
  }

  struct ITokenStorage has key {
    id: UID,
    markets: Bag
  }

  struct Account<phantom T> has key, store {
    id: UID,
    balance_value: u64,
    borrow_index: u256,
    principal: u256,
  }

  struct AccountStorage has key {
     id: UID,
     accounts: Bag, // get_coin_info -> address -> Account
     collateral_markets: Bag  // address -> vector<String> 
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

    transfer::share_object(
      AccountStorage {
        id: object::new(ctx),
        accounts: bag::new(ctx),
        collateral_markets: bag::new(ctx)
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
    accounts_storage: &mut AccountStorage, 
    interest_rate_model_storage: &mut InterestRateModelStorage,
    asset: Coin<T>,
    ctx: &mut TxContext
  ): Coin<IToken<T>> {
      let market = borrow_mut_market<T>(itoken_storage);

      let sender = tx_context::sender(ctx);

      if (!account_exists<T>(accounts_storage, sender)) {
          bag::add(
            bag::borrow_mut(&mut accounts_storage.accounts, get_coin_info<T>()),
            sender,
            Account<T> {
              id: object::new(ctx),
              balance_value: 0,
              borrow_index: 0,
              principal: 0,
            }
          );
      };

      accrue_internal<T>(market, interest_rate_model_storage, ctx);

      assert!(deposit_allowed<T>(market), ERROR_DEPOSIT_NOT_ALLOWED);

      let coin_value = coin::value(&asset);

      let shares = fdiv(coin_value, get_current_exchange_rate<T>(market));

      balance::join(&mut market.balance, coin::into_balance(asset));

      let account = borrow_mut_account<T>(accounts_storage, sender);

      account.balance_value = account.balance_value + coin_value;

      coin::from_balance(balance::increase_supply(&mut market.supply, shares), ctx)
  }

  public fun withdraw<T>(
    itoken_storage: &mut ITokenStorage, 
    accounts_storage: &mut AccountStorage, 
    interest_rate_model_storage: &mut InterestRateModelStorage,
    itoken_coin: Coin<IToken<T>>,
    ctx: &mut TxContext
  ): Coin<T> {
     let market = borrow_mut_market<T>(itoken_storage);
     accrue_internal<T>(market, interest_rate_model_storage, ctx);

    let underlying_to_redeem = fmul(coin::value(&itoken_coin), get_current_exchange_rate<T>(market));

    let sender = tx_context::sender(ctx);

    assert!(withdraw_allowed<T>(market, accounts_storage, sender, underlying_to_redeem), ERROR_WITHDRAW_NOT_ALLOWED);
    assert!(balance::value(&market.balance) >= underlying_to_redeem , ERROR_NOT_ENOUGH_CASH_TO_WITHDRAW);

    balance::decrease_supply(&mut market.supply, coin::into_balance(itoken_coin));

    let account = borrow_mut_account<T>(accounts_storage, sender);

    account.balance_value = account.balance_value - underlying_to_redeem; 

    coin::take(&mut market.balance, underlying_to_redeem, ctx)
  }

  public fun borrow<T>(
    itoken_storage: &mut ITokenStorage, 
    accounts_storage: &mut AccountStorage, 
    interest_rate_model_storage: &mut InterestRateModelStorage,
    borrow_value: u64,
    ctx: &mut TxContext
  ): Coin<T> {
    let market = borrow_mut_market<T>(itoken_storage);
    accrue_internal<T>(market, interest_rate_model_storage, ctx);

    assert!(balance::value(&market.balance) >= borrow_value, ERROR_NOT_ENOUGH_CASH_TO_LEND);
    assert!(borrow_allowed<T>(), ERROR_BORROW_NOT_ALLOWED);

    let account = borrow_mut_account<T>(accounts_storage, tx_context::sender(ctx));

    let new_borrow_balance = calculate_borrow_balance_of(account, market.borrow_index) + borrow_value;

    account.principal = (new_borrow_balance as u256);
    account.borrow_index = market.borrow_index;
    market.total_borrows = market.total_borrows + borrow_value;

    coin::take(&mut market.balance, borrow_value, ctx)
  }

  public fun repay<T>(
    itoken_storage: &mut ITokenStorage, 
    accounts_storage: &mut AccountStorage, 
    interest_rate_model_storage: &mut InterestRateModelStorage,
    asset: Coin<T>,
    ctx: &mut TxContext    
  ) {
    let market = borrow_mut_market<T>(itoken_storage);
    accrue_internal<T>(market, interest_rate_model_storage, ctx);
    
    assert!(repay_allowed<T>(),ERROR_REPAY_NOT_ALLOWED);

    let sender = tx_context::sender(ctx);

    let account = borrow_mut_account<T>(accounts_storage, sender);

    let coin_value = coin::value(&asset);

    let repay_amount = if (coin_value > (account.principal as u64)) { (account.principal as u64) } else { coin_value };

    if (coin_value > repay_amount) pay::split_and_transfer(&mut asset, coin_value - repay_amount, sender, ctx);

    balance::join(&mut market.balance, coin::into_balance(asset));

    account.principal = account.principal - (repay_amount as u256);
    account.borrow_index = market.borrow_index;
    market.total_borrows = market.total_borrows - repay_amount;
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

  public fun enter_market<T>(account_storage: &mut AccountStorage, ctx: &mut TxContext) {
    let sender = tx_context::sender(ctx);
    if (!bag::contains(&account_storage.collateral_markets, sender)) {
      bag::add(
       &mut account_storage.collateral_markets,
       sender,
       vector::empty<String>()
      );
    };

   let user_collateral_markets = borrow_mut_user_collateral_markets(account_storage, sender);

   let market_key = get_coin_info<T>();

   if (!vector::contains(user_collateral_markets, &market_key)) { 
      vector::push_back(user_collateral_markets, market_key);
    };
  }

  public fun exit_market<T>(account_storage: &mut AccountStorage, ctx: &mut TxContext) {
   let (is_present, index) = vector::index_of(borrow_user_collateral_markets(account_storage, tx_context::sender(ctx)), &get_coin_info<T>());

   if (is_present) { 
      vector::remove<String>(borrow_mut_user_collateral_markets(account_storage, tx_context::sender(ctx)), index);
    };
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

  fun borrow_account<T>(accounts_storage: &AccountStorage, user: address): &Account<T> {
    bag::borrow(bag::borrow(&accounts_storage.accounts, get_coin_info<T>()), user)
  }

  fun borrow_mut_account<T>(accounts_storage: &mut AccountStorage, user: address): &mut Account<T> {
    bag::borrow_mut(bag::borrow_mut(&mut accounts_storage.accounts, get_coin_info<T>()), user)
  }

  fun borrow_user_collateral_markets(accounts_storage: &AccountStorage, user: address): &vector<String> {
    bag::borrow<address, vector<String>>(&accounts_storage.collateral_markets, user)
  }

  fun borrow_mut_user_collateral_markets(accounts_storage: &mut AccountStorage, user: address): &mut vector<String> {
    bag::borrow_mut<address, vector<String>>(&mut accounts_storage.collateral_markets, user)
  }

  fun account_exists<T>(accounts_storage: &AccountStorage, user: address): bool {
    bag::contains(bag::borrow(&accounts_storage.accounts, get_coin_info<T>()), user)
  }

  fun calculate_borrow_balance_of<T>(account: &Account<T>, borrow_index: u256): u64 {
    if (account.principal == 0) { 0 } else { ((account.principal * borrow_index / account.borrow_index ) as u64) }
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
    accounts_storage: &mut AccountStorage, 
    ctx: &mut TxContext
    ) {
    let key = get_coin_info<T>();
    
    // Add the market
    bag::add(
      &mut itoken_storage.markets, 
      key,
      Market {
        id: object::new(ctx),
        total_reserves: 0,
        total_reserves_shares: 0,
        total_borrows: 0,
        accrued_epoch: tx_context::epoch(ctx),
        borrow_index: 0,
        balance: balance::zero<T>(),
        asset_off_set: 0,
        supply: balance::create_supply(IToken<T> {}),
        is_paused: false
      });

    // Add bag to store address -> account
    bag::add(
      &mut accounts_storage.accounts,
      key,
      bag::new(ctx)
    );  
  }

  public fun pause_market<T>(_: &ITokenAdminCap, itoken_storage: &mut ITokenStorage) {
    let market = borrow_mut_market<T>(itoken_storage);
    market.is_paused = true;
  }

  public fun unpause_market<T>(_: &ITokenAdminCap, itoken_storage: &mut ITokenStorage) {
    let market = borrow_mut_market<T>(itoken_storage);
    market.is_paused = false;
  }

  // Controller

  fun deposit_allowed<T>(market: &Market<T>): bool {
    assert!(!market.is_paused, ERROR_MARKET_IS_PAUSED);
    true
  }

  fun withdraw_allowed<T>(market: &Market<T>, account_storage: &AccountStorage, user: address, coin_value: u64): bool {
    assert!(!market.is_paused, ERROR_MARKET_IS_PAUSED);

    if (!bag::contains(&account_storage.collateral_markets, user)) return true;

    let user_collateral_market = borrow_user_collateral_markets(account_storage, user);

    if (!vector::contains(user_collateral_market, &get_coin_info<T>())) return true;

    if (does_user_have_enough_liquidity<T>(account_storage, user, coin_value)) return true;

    false
  }

  fun borrow_allowed<T>(): bool {
    true
  }

  fun repay_allowed<T>(): bool {
    true
  }

  fun does_user_have_enough_liquidity<T>(account_storage: &AccountStorage, user: address, coin_value: u64): bool {
    let user_collateral_markets = borrow_user_collateral_markets(account_storage, user);


    true
  }
}