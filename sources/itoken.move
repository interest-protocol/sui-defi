module whirpool::itoken {
  use std::ascii::{String};
  use std::vector;
  
  use sui::tx_context::{Self, TxContext};
  use sui::transfer;
  use sui::object::{Self, UID};
  use sui::bag::{Self, Bag};
  use sui::table::{Self, Table};
  use sui::balance::{Self, Supply, Balance};
  use sui::coin::{Self, Coin};
  use sui::pay;

  use whirpool::interest_rate_model::{Self, InterestRateModelStorage};
  use whirpool::oracle::{get_price, OracleStorage};
  use whirpool::utils::{get_coin_info};
  use whirpool::math::{fmul, fdiv, fmul_u256, one};

  const INITIAL_RESERVE_FACTOR_MANTISSA: u64 = 200000000; // 0.2e9 or 20%
  const PROTOCOL_SEIZE_SHARE_MANTISSA: u64 = 28000000; // 0.028e9 or 2.8%
  const INITIAL_EXCHANGE_RATE_MANTISSA: u64 = 200000000; // 1e10

  const ERROR_DEPOSIT_NOT_ALLOWED: u64 = 1;
  const ERROR_WITHDRAW_NOT_ALLOWED: u64 = 2;
  const ERROR_NOT_ENOUGH_CASH_TO_WITHDRAW: u64 = 3;
  const ERROR_NOT_ENOUGH_CASH_TO_LEND: u64 = 4;
  const ERROR_BORROW_NOT_ALLOWED: u64 = 5;
  const ERROR_REPAY_NOT_ALLOWED: u64 = 6;
  const ERROR_MARKET_IS_PAUSED: u64 = 7;
  const ERROR_MARKET_NOT_UP_TO_DATE: u64 = 8;

  struct ITokenAdminCap has key {
    id: UID
  }

  struct IToken<phantom T> has drop {}

  struct MarketData has key, store {
    id: UID,
    total_reserves: u64,
    total_reserves_shares: u64,
    total_borrows: u64,
    accrued_epoch: u64,
    borrow_cap: u64,
    borrow_index: u256,
    balance_value: u64,
    supply_value: u64,
    is_paused: bool,
    ltv: u64,
    reserve_factor: u64
  }

  struct MarketTokens<phantom T> has key, store {
    balance: Balance<T>,
    supply: Supply<IToken<T>>,
  }

  struct Liquidation has key, store {
    penalty_fee: u64,
    protocol_percentage: u64
  }

  struct ITokenStorage has key {
    id: UID,
    markets_data: Table<String, MarketData>,
    liquidation: Table<String, Liquidation>,
    markets_tokens: Bag
  }

  struct Account has key, store {
    id: UID,
    balance_value: u64,
    borrow_index: u256,
    principal: u256,
  }

  struct AccountStorage has key {
     id: UID,
     accounts: Bag, // get_coin_info -> address -> Account
     markets_in: Bag  // address -> vector<String> 
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
        markets_data: table::new(ctx),
        liquidation: table::new(ctx),
        markets_tokens: bag::new(ctx)
      }
    );

    transfer::share_object(
      AccountStorage {
        id: object::new(ctx),
        accounts: bag::new(ctx),
        markets_in: bag::new(ctx)
      }
    );
  }

  public fun accrue<T>(
    itoken_storage: &mut ITokenStorage, 
    interest_rate_model_storage: &InterestRateModelStorage, 
    ctx: &TxContext
  ) {
    accrue_internal<T>(borrow_mut_market_data<T>(&mut itoken_storage.markets_data), interest_rate_model_storage, ctx);
  }

  public fun deposit<T>(
    itoken_storage: &mut ITokenStorage, 
    accounts_storage: &mut AccountStorage, 
    interest_rate_model_storage: &mut InterestRateModelStorage,
    asset: Coin<T>,
    ctx: &mut TxContext
  ): Coin<IToken<T>> {
      let market_data = borrow_mut_market_data<T>(&mut itoken_storage.markets_data);
      let market_tokens = borrow_mut_market_tokens<T>(&mut itoken_storage.markets_tokens);

      let sender = tx_context::sender(ctx);

      if (!account_exists<T>(accounts_storage, sender)) {
          bag::add(
            bag::borrow_mut(&mut accounts_storage.accounts, get_coin_info<T>()),
            sender,
            Account {
              id: object::new(ctx),
              balance_value: 0,
              borrow_index: 0,
              principal: 0,
            }
          );
      };

      accrue_internal<T>(market_data, interest_rate_model_storage, ctx);

      assert!(deposit_allowed<T>(market_data), ERROR_DEPOSIT_NOT_ALLOWED);

      let asset_value = coin::value(&asset);

      let shares = fdiv(asset_value, get_current_exchange_rate(market_data));

      balance::join(&mut market_tokens.balance, coin::into_balance(asset));
      market_data.balance_value = market_data.balance_value + asset_value;

      let account = borrow_mut_account<T>(accounts_storage, sender);

      account.balance_value = account.balance_value + asset_value;

      market_data.supply_value = market_data.supply_value + shares;
      coin::from_balance(balance::increase_supply(&mut market_tokens.supply, shares), ctx)
  }

  public fun withdraw<T>(
    itoken_storage: &mut ITokenStorage, 
    accounts_storage: &mut AccountStorage, 
    interest_rate_model_storage: &mut InterestRateModelStorage,
    itoken_coin: Coin<IToken<T>>,
    ctx: &mut TxContext
  ): Coin<T> {
    let market_data = borrow_mut_market_data<T>(&mut itoken_storage.markets_data);
    let market_tokens = borrow_mut_market_tokens<T>(&mut itoken_storage.markets_tokens);
    
    accrue_internal<T>(market_data, interest_rate_model_storage, ctx);

    let itoken_value = coin::value(&itoken_coin);

    let underlying_to_redeem = fmul(itoken_value, get_current_exchange_rate(market_data));

    let sender = tx_context::sender(ctx);

    assert!(withdraw_allowed<T>(market_data, accounts_storage, sender, underlying_to_redeem), ERROR_WITHDRAW_NOT_ALLOWED);
    assert!(market_data.balance_value >= underlying_to_redeem , ERROR_NOT_ENOUGH_CASH_TO_WITHDRAW);

    market_data.supply_value = market_data.supply_value - itoken_value; 
    balance::decrease_supply(&mut market_tokens.supply, coin::into_balance(itoken_coin));

    let account = borrow_mut_account<T>(accounts_storage, sender);

    account.balance_value = account.balance_value - underlying_to_redeem; 

    market_data.balance_value =  market_data.balance_value - underlying_to_redeem;
    coin::take(&mut market_tokens.balance, underlying_to_redeem, ctx)
  }

  public fun borrow<T>(
    itoken_storage: &mut ITokenStorage, 
    accounts_storage: &mut AccountStorage, 
    interest_rate_model_storage: &mut InterestRateModelStorage,
    borrow_value: u64,
    ctx: &mut TxContext
  ): Coin<T> {
    let market_data = borrow_mut_market_data<T>(&mut itoken_storage.markets_data);
    let market_tokens = borrow_mut_market_tokens<T>(&mut itoken_storage.markets_tokens);

    accrue_internal<T>(market_data, interest_rate_model_storage, ctx);

    assert!(market_data.balance_value >= borrow_value, ERROR_NOT_ENOUGH_CASH_TO_LEND);
    assert!(borrow_allowed<T>(), ERROR_BORROW_NOT_ALLOWED);

    let sender = tx_context::sender(ctx);

    if (!account_exists<T>(accounts_storage, sender)) {
          bag::add(
            bag::borrow_mut(&mut accounts_storage.accounts, get_coin_info<T>()),
            sender,
            Account {
              id: object::new(ctx),
              balance_value: 0,
              borrow_index: 0,
              principal: 0,
            }
          );
    };

    let account = borrow_mut_account<T>(accounts_storage, sender);

    let new_borrow_balance = calculate_borrow_balance_of(account, market_data.borrow_index) + borrow_value;

    account.principal = (new_borrow_balance as u256);
    account.borrow_index = market_data.borrow_index;
    market_data.total_borrows = market_data.total_borrows + borrow_value;

    market_data.balance_value = market_data.balance_value - borrow_value;
    coin::take(&mut market_tokens.balance, borrow_value, ctx)
  }

  public fun repay<T>(
    itoken_storage: &mut ITokenStorage, 
    accounts_storage: &mut AccountStorage, 
    interest_rate_model_storage: &mut InterestRateModelStorage,
    asset: Coin<T>,
    ctx: &mut TxContext    
  ) {
    let market_data = borrow_mut_market_data<T>(&mut itoken_storage.markets_data);
    let market_tokens = borrow_mut_market_tokens<T>(&mut itoken_storage.markets_tokens);

    accrue_internal<T>(market_data, interest_rate_model_storage, ctx);
    
    assert!(repay_allowed<T>(),ERROR_REPAY_NOT_ALLOWED);

    let sender = tx_context::sender(ctx);

    let account = borrow_mut_account<T>(accounts_storage, sender);

    let asset_value = coin::value(&asset);

    let repay_amount = if (asset_value > (account.principal as u64)) { (account.principal as u64) } else { asset_value };

    if (asset_value > repay_amount) pay::split_and_transfer(&mut asset, asset_value - repay_amount, sender, ctx);

    balance::join(&mut market_tokens.balance, coin::into_balance(asset));
    market_data.balance_value = market_data.balance_value + asset_value;

    account.principal = account.principal - (repay_amount as u256);
    account.borrow_index = market_data.borrow_index;
    market_data.total_borrows = market_data.total_borrows - repay_amount;
  }

  public fun get_borrow_rate_per_epoch<T>(
    market: &MarketData, 
    interest_rate_model_storage: &InterestRateModelStorage
    ): u64 {
    interest_rate_model::get_borrow_rate_per_epoch<T>(
      interest_rate_model_storage,
      market.balance_value,
      market.total_borrows,
      market.total_reserves
    )
  }

  public fun enter_market<T>(account_storage: &mut AccountStorage, ctx: &mut TxContext) {
    let sender = tx_context::sender(ctx);
    if (!bag::contains(&account_storage.markets_in, sender)) {
      bag::add(
       &mut account_storage.markets_in,
       sender,
       vector::empty<String>()
      );
    };

   let user_markets_in = borrow_mut_user_markets_in(&mut account_storage.accounts, sender);

   let market_key = get_coin_info<T>();

   if (!vector::contains(user_markets_in, &market_key)) { 
      vector::push_back(user_markets_in, market_key);
    };
  }

  public fun exit_market<T>(account_storage: &mut AccountStorage, ctx: &mut TxContext) {
   let (is_present, index) = vector::index_of(borrow_user_markets_in(&account_storage.markets_in, tx_context::sender(ctx)), &get_coin_info<T>());
  }

  public fun get_account_balances<T>(
    itoken_storage: &mut ITokenStorage, 
    account_storage: &AccountStorage,
    interest_rate_model_storage: &InterestRateModelStorage, 
    user: address, 
    ctx: &mut TxContext
    ): (u64, u64) {
    let market_data = borrow_mut_market_data<T>(&mut itoken_storage.markets_data);
    let account = borrow_account<T>(account_storage, user);

    if (tx_context::epoch(ctx) > market_data.accrued_epoch) accrue_internal<T>(market_data, interest_rate_model_storage, ctx);
    
    get_account_balances_internal(market_data, account, ctx)
  }

  fun get_account_balances_internal(
    market_data: &MarketData,
    account: &Account,
    ctx: &mut TxContext
  ): (u64, u64) {
     assert!(market_data.accrued_epoch == tx_context::epoch(ctx), ERROR_MARKET_NOT_UP_TO_DATE);

     (account.balance_value, calculate_borrow_balance_of(account, market_data.borrow_index))
  }

  fun accrue_internal<T>(
    market_data: &mut MarketData, 
    interest_rate_model_storage: &InterestRateModelStorage, 
    ctx: &TxContext
  ) {
    let epochs_delta = get_epochs_delta_internal(market_data, ctx);

    if (epochs_delta == 0) return;

    let interest_rate = epochs_delta * get_borrow_rate_per_epoch<T>(market_data, interest_rate_model_storage);

    let interest_rate_amount = fmul(interest_rate, market_data.total_borrows);

    market_data.accrued_epoch = tx_context::epoch(ctx);
    market_data.total_borrows = interest_rate_amount +  market_data.total_borrows;
    market_data.total_reserves = fmul(interest_rate_amount, market_data.reserve_factor) + market_data.total_reserves;
    market_data.borrow_index = fmul_u256((interest_rate_amount as u256), market_data.borrow_index) + market_data.borrow_index;
  }

  fun get_epochs_delta_internal(market: &MarketData, ctx: &TxContext): u64 {
      tx_context::epoch(ctx) - market.accrued_epoch
  }

  fun get_current_exchange_rate(market: &MarketData): u64 {
      if (market.supply_value == 0) {
        INITIAL_EXCHANGE_RATE_MANTISSA
      } else {
        fmul(market.balance_value + market.total_borrows - market.total_reserves, market.supply_value)
      }
  }

  fun borrow_market_tokens<T>(markets_tokens: &Bag): &MarketTokens<T> {
    bag::borrow(markets_tokens, get_coin_info<T>())
  }

  fun borrow_mut_market_tokens<T>(markets_tokens: &mut Bag): &mut MarketTokens<T> {
    bag::borrow_mut(markets_tokens, get_coin_info<T>())
  }

  fun borrow_market_data<T>(markets_data: &Table<String, MarketData>): &MarketData {
    table::borrow(markets_data, get_coin_info<T>())
  }

  fun borrow_mut_market_data<T>(markets_data: &mut Table<String, MarketData>): &mut MarketData {
    table::borrow_mut(markets_data, get_coin_info<T>())
  }

  fun borrow_account<T>(accounts_storage: &AccountStorage, user: address): &Account {
    bag::borrow(bag::borrow(&accounts_storage.accounts, get_coin_info<T>()), user)
  }

  fun borrow_mut_account<T>(accounts_storage: &mut AccountStorage, user: address): &mut Account {
    bag::borrow_mut(bag::borrow_mut(&mut accounts_storage.accounts, get_coin_info<T>()), user)
  }

  fun borrow_user_markets_in(markets_in: &Bag, user: address): &vector<String> {
    bag::borrow<address, vector<String>>(markets_in, user)
  }

  fun borrow_mut_user_markets_in(markets_in: &mut Bag, user: address): &mut vector<String> {
    bag::borrow_mut<address, vector<String>>(markets_in, user)
  }

  fun account_exists<T>(accounts_storage: &AccountStorage, user: address): bool {
    bag::contains(bag::borrow(&accounts_storage.accounts, get_coin_info<T>()), user)
  }

  fun calculate_borrow_balance_of(account: &Account, borrow_index: u256): u64 {
    if (account.principal == 0) { 0 } else { ((account.principal * borrow_index / account.borrow_index ) as u64) }
  }

  entry public fun set_interest_rate_data<T>(
    _: &ITokenAdminCap,
    itoken_storage: &mut ITokenStorage, 
    interest_rate_model_storage: &mut InterestRateModelStorage,
    base_rate_per_year: u64,
    multiplier_per_year: u64,
    jump_multiplier_per_year: u64,
    kink: u64,
    ctx: &mut TxContext
  ) {
    accrue_internal<T>(borrow_mut_market_data<T>(&mut itoken_storage.markets_data), interest_rate_model_storage, ctx);

    interest_rate_model::set_interest_rate_data<T>(
      interest_rate_model_storage,
      base_rate_per_year,
      multiplier_per_year,
      jump_multiplier_per_year,
      kink,
      ctx
    )
  } 

  entry public fun update_liquidation<T>(
    _: &ITokenAdminCap, 
    itoken_storage: &mut ITokenStorage,
    penalty_fee: u64,
    protocol_percentage: u64,
  ) {
    let liquidation = table::borrow_mut(&mut itoken_storage.liquidation, get_coin_info<T>());
    liquidation.penalty_fee = penalty_fee;
    liquidation.protocol_percentage = protocol_percentage;
  }

  entry public fun update_rserve_factor<T>(
    _: &ITokenAdminCap, 
    itoken_storage: &mut ITokenStorage,
    reserve_factor: u64
  ) {
    let market_data = borrow_mut_market_data<T>(&mut itoken_storage.markets_data);
    market_data.reserve_factor = reserve_factor;
  }

  entry public fun create_market<T>(
    _: &ITokenAdminCap, 
    itoken_storage: &mut ITokenStorage,
    accounts_storage: &mut AccountStorage, 
    borrow_cap: u64,
    ltv: u64,
    penalty_fee: u64,
    protocol_percentage: u64,
    ctx: &mut TxContext
    ) {
    let key = get_coin_info<T>();
    
    // Add the market data
    table::add(
      &mut itoken_storage.markets_data, 
      key,
      MarketData {
        id: object::new(ctx),
        total_reserves: 0,
        total_reserves_shares: 0,
        total_borrows: 0,
        accrued_epoch: tx_context::epoch(ctx),
        borrow_cap,
        borrow_index: 0,
        balance_value: 0,
        supply_value: 0,
        is_paused: false,
        ltv,
        reserve_factor: INITIAL_RESERVE_FACTOR_MANTISSA
    });

    table::add(
      &mut itoken_storage.liquidation,
      key,
      Liquidation {
        penalty_fee,
        protocol_percentage
      }
    );

    // Add the market tokens
    bag::add(
      &mut itoken_storage.markets_tokens, 
      key,
      MarketTokens {
        balance: balance::zero<T>(),
        supply: balance::create_supply(IToken<T> {}),
    });  

    // Add bag to store address -> account
    bag::add(
      &mut accounts_storage.accounts,
      key,
      bag::new(ctx)
    );  
  }

  entry public fun pause_market<T>(_: &ITokenAdminCap, itoken_storage: &mut ITokenStorage) {
    let market_data = borrow_mut_market_data<T>(&mut itoken_storage.markets_data);
    market_data.is_paused = true;
  }

  entry public fun unpause_market<T>(_: &ITokenAdminCap, itoken_storage: &mut ITokenStorage) {
    let market_data = borrow_mut_market_data<T>(&mut itoken_storage.markets_data);
    market_data.is_paused = false;
  }

  entry public fun set_borrow_cap<T>(
    _: &ITokenAdminCap, 
    itoken_storage: &mut ITokenStorage,
    borrow_cap: u64
    ) {
    let market_data = borrow_mut_market_data<T>(&mut itoken_storage.markets_data);
     
     market_data.borrow_cap = borrow_cap;
  }

  // Controller

  fun deposit_allowed<T>(market_data: &MarketData): bool {
    assert!(!market_data.is_paused, ERROR_MARKET_IS_PAUSED);
    true
  }

  fun withdraw_allowed<T>(marke_data: &MarketData, account_storage: &AccountStorage, user: address, coin_value: u64): bool {
    assert!(!marke_data.is_paused, ERROR_MARKET_IS_PAUSED);

    if (!bag::contains(&account_storage.markets_in, user)) return true;

    let user_collateral_market = borrow_user_markets_in(&account_storage.markets_in, user);

    if (!vector::contains(user_collateral_market, &get_coin_info<T>())) return true;

    // if (is_user_solvent<T>(account_storage, user, coin_value, 0)) return true;

    false
  }

  fun borrow_allowed<T>(): bool {
    true
  }

  fun repay_allowed<T>(): bool {
    true
  }

  fun is_user_solvent(
    itoken_storage: &ITokenStorage, 
    account_storage: &mut AccountStorage, 
    oracle_storage: &OracleStorage,
    modified_market_key: String,
    user: address,
    withdraw_coin_value: u64,
    borrow_coin_value: u64,
    ctx: &mut TxContext
  ): bool {
    let user_markets_in = borrow_mut_user_markets_in(&mut account_storage.markets_in, user);

    let index = 0;
    let length = vector::length(user_markets_in);

    let markets_in_copy = vector::empty<String>();

    let total_collateral_in_usd = 0;
    let total_borrows_in_usd = 0;
    
    while(index < length) {

      let key = vector::pop_back(user_markets_in);
      vector::push_back(&mut markets_in_copy, key);

      let is_modified_market = key == modified_market_key;

      let market_data = table::borrow(&itoken_storage.markets_data, key);
      let account = bag::borrow<address, Account>(bag::borrow<String, Bag>(&account_storage.accounts, key), user);
      let (_collateral_balance, _borrow_balance) = get_account_balances_internal(market_data, account, ctx);

      let collateral_balance = if (is_modified_market) { _collateral_balance - withdraw_coin_value } else { _collateral_balance };
      let borrow_balance = if (is_modified_market) { _borrow_balance + borrow_coin_value } else { _borrow_balance };

      let (price, decimals) = get_price(oracle_storage, key);

      let price_normalized = (((price as u256) * one()) / (decimals as u256) as u64);

      total_collateral_in_usd = total_collateral_in_usd + fmul(fmul(collateral_balance, price_normalized), market_data.ltv);
      total_borrows_in_usd = total_borrows_in_usd + fmul(borrow_balance, price_normalized);

      index = index + 1;
    };

    bag::remove<address, vector<String>>(&mut account_storage.markets_in, user);
    bag::add(&mut account_storage.markets_in, user, markets_in_copy);

    total_collateral_in_usd > total_borrows_in_usd
  }
}