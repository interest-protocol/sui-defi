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
  use sui::math;

  use whirpool::dnr::{Self, DNR, DineroStorage};
  use whirpool::interest_rate_model::{Self, InterestRateModelStorage};
  use whirpool::oracle::{Self, OracleStorage};
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
  const ERROR_BORROW_CAP_LIMIT_REACHED: u64 = 9;
  const ERROR_ZERO_ORACLE_PRICE: u64 = 10;
  const ERROR_MARKET_EXIT_LOAN_OPEN: u64 = 11;
  const ERROR_USER_IS_INSOLVENT: u64 = 12;
  const ERROR_NOT_ENOUGH_RESERVES: u64 = 13;
  const ERROR_CAN_NOT_USE_DNR: u64 = 14;
  const ERROR_DNR_OPERAtiON_NOT_ALLOWED: u64 = 15;
  const ERROR_USER_IS_SOLVENT: u64 = 16;
  const ERROR_ACCOUNT_COLLATERAL_DOES_EXIST: u64 = 17;
  const ERROR_ACCOUNT_LOAN_DOES_EXIST: u64 = 18;
  const ERROR_ZERO_LIQUIDATION_AMOUNT: u64 = 19;
  const ERROR_LIQUIDATOR_IS_BORROWER: u64 = 20;

  struct ITokenAdminCap has key {
    id: UID
  }

  struct IToken<phantom T> has drop {}

  struct MarketData has key, store {
    id: UID,
    total_reserves: u64,
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
    market_data: Table<String, MarketData>,
    liquidation: Table<String, Liquidation>,
    market_tokens: Bag // get_coin_info -> MarketTokens
  }

  struct Account has key, store {
    id: UID,
    balance_value: u64,
    borrow_index: u256,
    principal: u256,
  }

  struct AccountStorage has key {
     id: UID,
     accounts: Table<String, Table<address, Account>>, // get_coin_info -> address -> Account
     markets_in: Table<address, vector<String>>  
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
        market_data: table::new(ctx),
        liquidation: table::new(ctx),
        market_tokens: bag::new(ctx)
      }
    );

    transfer::share_object(
      AccountStorage {
        id: object::new(ctx),
        accounts: table::new(ctx),
        markets_in: table::new(ctx)
      }
    );
  }

  public fun accrue<T>(
    itoken_storage: &mut ITokenStorage, 
    interest_rate_model_storage: &InterestRateModelStorage, 
    dinero_storage: &DineroStorage,
    ctx: &TxContext
  ) {
    let market_key = get_coin_info<T>();
    accrue_internal(borrow_mut_market_data(&mut itoken_storage.market_data, market_key), interest_rate_model_storage, dinero_storage, market_key, ctx);
  }

  public fun deposit<T>(
    itoken_storage: &mut ITokenStorage, 
    account_storage: &mut AccountStorage, 
    interest_rate_model_storage: &InterestRateModelStorage,
    dinero_storage: &DineroStorage,
    asset: Coin<T>,
    ctx: &mut TxContext
  ): Coin<IToken<T>> {
      let market_key = get_coin_info<T>();
      assert!(market_key != get_coin_info<DNR>(), ERROR_DNR_OPERAtiON_NOT_ALLOWED);

      let market_data = borrow_mut_market_data(&mut itoken_storage.market_data, market_key);
      let market_tokens = borrow_mut_market_tokens<T>(&mut itoken_storage.market_tokens, market_key);

      let sender = tx_context::sender(ctx);

      init_account(account_storage, sender, market_key, ctx);

      accrue_internal(market_data, interest_rate_model_storage, dinero_storage, market_key, ctx);

      let asset_value = coin::value(&asset);

      let shares = fdiv(asset_value, get_current_exchange_rate(market_data));

      balance::join(&mut market_tokens.balance, coin::into_balance(asset));
      market_data.balance_value = market_data.balance_value + asset_value;

      let account = borrow_mut_account(account_storage, sender, market_key);

      account.balance_value = account.balance_value + asset_value;

      market_data.supply_value = market_data.supply_value + shares;
      let itoken = coin::from_balance(balance::increase_supply(&mut market_tokens.supply, shares), ctx);
      // Check should be the last action after all mutations
      assert!(deposit_allowed(market_data), ERROR_DEPOSIT_NOT_ALLOWED);
      itoken
  }   

  public fun withdraw<T>(
    itoken_storage: &mut ITokenStorage, 
    account_storage: &mut AccountStorage, 
    interest_rate_model_storage: &InterestRateModelStorage,
    dinero_storage: &DineroStorage,
    oracle_storage: &OracleStorage,
    itoken_coin: Coin<IToken<T>>,
    ctx: &mut TxContext
  ): Coin<T> {
    let market_key = get_coin_info<T>();
    assert!(market_key != get_coin_info<DNR>(), ERROR_DNR_OPERAtiON_NOT_ALLOWED);

    let market_data = borrow_mut_market_data(&mut itoken_storage.market_data, market_key);
    let market_tokens = borrow_mut_market_tokens<T>(&mut itoken_storage.market_tokens, market_key);
    
    accrue_internal(market_data, interest_rate_model_storage, dinero_storage, market_key, ctx);

    let itoken_value = coin::value(&itoken_coin);

    let underlying_to_redeem = fmul(itoken_value, get_current_exchange_rate(market_data));

    let sender = tx_context::sender(ctx);

    assert!(market_data.balance_value >= underlying_to_redeem , ERROR_NOT_ENOUGH_CASH_TO_WITHDRAW);

    market_data.supply_value = market_data.supply_value - itoken_value; 
    balance::decrease_supply(&mut market_tokens.supply, coin::into_balance(itoken_coin));

    let account = borrow_mut_account(account_storage, sender, market_key);

    account.balance_value = account.balance_value - underlying_to_redeem; 

    let underlying_coin = coin::take(&mut market_tokens.balance, underlying_to_redeem, ctx);

    market_data.balance_value =  market_data.balance_value - underlying_to_redeem;
    // Check should be the last action after all mutations
    assert!(withdraw_allowed(
      &mut itoken_storage.market_data, 
      account_storage, oracle_storage, 
      interest_rate_model_storage, 
      dinero_storage, 
      market_key, 
      sender, 
      underlying_to_redeem, 
      ctx), 
    ERROR_WITHDRAW_NOT_ALLOWED);

    underlying_coin
  }

  public fun borrow<T>(
    itoken_storage: &mut ITokenStorage, 
    account_storage: &mut AccountStorage, 
    interest_rate_model_storage: &InterestRateModelStorage,
    dinero_storage: &DineroStorage,
    oracle_storage: &OracleStorage,
    borrow_value: u64,
    ctx: &mut TxContext
  ): Coin<T> {
    let market_key = get_coin_info<T>();

    assert!(market_key != get_coin_info<DNR>(), ERROR_DNR_OPERAtiON_NOT_ALLOWED);

    let market_data = borrow_mut_market_data(&mut itoken_storage.market_data, market_key);
    let market_tokens = borrow_mut_market_tokens<T>(&mut itoken_storage.market_tokens, market_key);

    accrue_internal(market_data, interest_rate_model_storage, dinero_storage, market_key, ctx);

    assert!(market_data.balance_value >= borrow_value, ERROR_NOT_ENOUGH_CASH_TO_LEND);

    let sender = tx_context::sender(ctx);

    init_account(account_storage, sender, market_key, ctx);

    init_markets_in(account_storage, sender);

    let account = borrow_mut_account(account_storage, sender, market_key);

    let new_borrow_balance = calculate_borrow_balance_of(account, market_data.borrow_index) + borrow_value;

    account.principal = (new_borrow_balance as u256);
    account.borrow_index = market_data.borrow_index;
    market_data.total_borrows = market_data.total_borrows + borrow_value;

    market_data.balance_value = market_data.balance_value - borrow_value;

    let loan_coin = coin::take(&mut market_tokens.balance, borrow_value, ctx);
    // Check should be the last action after all mutations
    assert!(borrow_allowed(
      &mut itoken_storage.market_data, 
      account_storage, 
      oracle_storage, 
      interest_rate_model_storage, 
      dinero_storage, 
      market_key, 
      sender, 
      borrow_value, 
      ctx), 
    ERROR_BORROW_NOT_ALLOWED);

    loan_coin
  }

  public fun repay<T>(
    itoken_storage: &mut ITokenStorage, 
    account_storage: &mut AccountStorage, 
    interest_rate_model_storage: &InterestRateModelStorage,
    dinero_storage: &DineroStorage,
    asset: Coin<T>,
    ctx: &mut TxContext    
  ) {
    let market_key = get_coin_info<T>();

    assert!(market_key != get_coin_info<DNR>(), ERROR_DNR_OPERAtiON_NOT_ALLOWED);

    let market_data = borrow_mut_market_data(&mut itoken_storage.market_data, market_key);
    let market_tokens = borrow_mut_market_tokens<T>(&mut itoken_storage.market_tokens, market_key);

    accrue_internal(market_data, interest_rate_model_storage, dinero_storage, market_key, ctx);
    
    let sender = tx_context::sender(ctx);

    let account = borrow_mut_account(account_storage, sender, market_key);

    let asset_value = coin::value(&asset);

    let repay_amount = if (asset_value > (account.principal as u64)) { (account.principal as u64) } else { asset_value };

    if (asset_value > repay_amount) pay::split_and_transfer(&mut asset, asset_value - repay_amount, sender, ctx);

    balance::join(&mut market_tokens.balance, coin::into_balance(asset));
    market_data.balance_value = market_data.balance_value + repay_amount;

    account.principal = account.principal - (repay_amount as u256);
    account.borrow_index = market_data.borrow_index;
    market_data.total_borrows = market_data.total_borrows - repay_amount;
    assert!(repay_allowed(market_data),ERROR_REPAY_NOT_ALLOWED);
  }

  public fun get_borrow_rate_per_epoch<T>(
    market: &MarketData, 
    interest_rate_model_storage: &InterestRateModelStorage,
    dinero_storage: &DineroStorage,
    ): u64 {
    get_borrow_rate_per_epoch_internal(
      market,
      interest_rate_model_storage,
      dinero_storage,
      get_coin_info<T>()
    )
  }

  fun get_borrow_rate_per_epoch_internal(
    market: &MarketData, 
    interest_rate_model_storage: &InterestRateModelStorage,
    dinero_storage: &DineroStorage,
    market_key: String,
    ): u64 {
      if (get_coin_info<DNR>() == market_key) {
        dnr::get_interest_rate_per_epoch(dinero_storage)
      } else {
        interest_rate_model::get_borrow_rate_per_epoch(
          interest_rate_model_storage,
          market_key,
          market.balance_value,
          market.total_borrows,
          market.total_reserves
        )
      }
  }

  public fun enter_market<T>(account_storage: &mut AccountStorage, ctx: &mut TxContext) {
    let sender = tx_context::sender(ctx);

    init_markets_in(account_storage, sender);

   let user_markets_in = borrow_mut_user_markets_in(&mut account_storage.markets_in, sender);

   let market_key = get_coin_info<T>();

   if (!vector::contains(user_markets_in, &market_key)) { 
      vector::push_back(user_markets_in, market_key);
    };
  }

  public fun exit_market<T>(
    itoken_storage: &mut ITokenStorage, 
    account_storage: &mut AccountStorage, 
    interest_rate_model_storage: &InterestRateModelStorage,
    dinero_storage: &DineroStorage,
    oracle_storage: &OracleStorage,
    ctx: &mut TxContext
  ) {
    let market_key = get_coin_info<T>();
    let sender = tx_context::sender(ctx);
    let account = borrow_account(account_storage, sender, market_key);

   assert!(account.principal == 0, ERROR_MARKET_EXIT_LOAN_OPEN);

   let user_markets_in = borrow_mut_user_markets_in(&mut account_storage.markets_in, sender);

   let (is_present, index) = vector::index_of(user_markets_in, &market_key);

   if (is_present) {
    let _ = vector::remove(user_markets_in, index);
   };

    assert!(is_user_solvent(
      &mut itoken_storage.market_data, 
      account_storage, oracle_storage, 
      interest_rate_model_storage, 
      dinero_storage, market_key, 
      sender, 
      0, 
      0, 
      ctx), 
    ERROR_USER_IS_INSOLVENT);
  }

  public fun get_account_balances<T>(
    itoken_storage: &mut ITokenStorage, 
    account_storage: &AccountStorage,
    interest_rate_model_storage: &InterestRateModelStorage, 
    dinero_storage: &DineroStorage,
    user: address, 
    ctx: &mut TxContext
    ): (u64, u64) {
    let market_key = get_coin_info<T>();  
    let market_data = borrow_mut_market_data(&mut itoken_storage.market_data, market_key);
    let account = borrow_account(account_storage, user, market_key);
    
    get_account_balances_internal(market_data, account, interest_rate_model_storage, dinero_storage, market_key, ctx)
  }

  fun get_account_balances_internal(
    market_data: &mut MarketData,
    account: &Account,
    interest_rate_model_storage: &InterestRateModelStorage,
    dinero_storage: &DineroStorage,
    market_key: String, 
    ctx: &mut TxContext
  ): (u64, u64) {
    if (tx_context::epoch(ctx) > market_data.accrued_epoch) accrue_internal(market_data, interest_rate_model_storage, dinero_storage, market_key, ctx);

     (account.balance_value, calculate_borrow_balance_of(account, market_data.borrow_index))
  }

  fun accrue_internal(
    market_data: &mut MarketData, 
    interest_rate_model_storage: &InterestRateModelStorage,
    dinero_storage: &DineroStorage,
    market_key: String, 
    ctx: &TxContext
  ) {
    let epochs_delta = get_epochs_delta_internal(market_data, ctx);

    if (epochs_delta == 0) return;

    let interest_rate = epochs_delta * get_borrow_rate_per_epoch_internal(market_data, interest_rate_model_storage, dinero_storage, market_key);

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

  fun borrow_market_tokens<T>(market_tokens: &Bag, market_key: String): &MarketTokens<T> {
    bag::borrow(market_tokens, market_key)
  }

  fun borrow_mut_market_tokens<T>(market_tokens: &mut Bag, market_key: String): &mut MarketTokens<T> {
    bag::borrow_mut(market_tokens, market_key)
  }

  fun borrow_market_data(market_data: &Table<String, MarketData>, market_key: String): &MarketData {
    table::borrow(market_data, market_key)
  }

  fun borrow_mut_market_data(market_data: &mut Table<String, MarketData>, market_key: String): &mut MarketData {
    table::borrow_mut(market_data, market_key)
  }

  fun borrow_account(account_storage: &AccountStorage, user: address, market_key: String): &Account {
    table::borrow(table::borrow(&account_storage.accounts, market_key), user)
  }

  fun borrow_mut_account(account_storage: &mut AccountStorage, user: address, market_key: String): &mut Account {
    table::borrow_mut(table::borrow_mut(&mut account_storage.accounts, market_key), user)
  }

  fun borrow_user_markets_in(markets_in: &Table<address, vector<String>>, user: address): &vector<String> {
    table::borrow(markets_in, user)
  }

  fun borrow_mut_user_markets_in(markets_in: &mut Table<address, vector<String>>, user: address): &mut vector<String> {
    table::borrow_mut(markets_in, user)
  }

  fun account_exists(account_storage: &AccountStorage, user: address, market_key: String): bool {
    table::contains(table::borrow(&account_storage.accounts, market_key), user)
  }

  fun init_account(account_storage: &mut AccountStorage, user: address, key: String, ctx: &mut TxContext) {
    if (!account_exists(account_storage, user, key)) {
          table::add(
            table::borrow_mut(&mut account_storage.accounts, key),
            user,
            Account {
              id: object::new(ctx),
              balance_value: 0,
              borrow_index: 0,
              principal: 0,
            }
        );
    };
  }

  fun init_markets_in(account_storage: &mut AccountStorage, user: address) {
    if (!table::contains(&account_storage.markets_in, user)) {
      table::add(
       &mut account_storage.markets_in,
       user,
       vector::empty<String>()
      );
    };
  }

  fun calculate_borrow_balance_of(account: &Account, borrow_index: u256): u64 {
    if (account.principal == 0) { 0 } else { ((account.principal * borrow_index / account.borrow_index ) as u64) }
  }

  fun get_price(oracle_storage: &OracleStorage, key: String): u64 {
    let (price, decimals) = if (key == get_coin_info<DNR>()) { (one(), 18) } else { oracle::get_price(oracle_storage, key) };
    (((price as u256) * one()) / (math::pow(10, decimals) as u256) as u64)
  }

  entry public fun set_interest_rate_data<T>(
    _: &ITokenAdminCap,
    itoken_storage: &mut ITokenStorage, 
    interest_rate_model_storage: &mut InterestRateModelStorage,
    dinero_storage: &DineroStorage,
    base_rate_per_year: u64,
    multiplier_per_year: u64,
    jump_multiplier_per_year: u64,
    kink: u64,
    ctx: &mut TxContext
  ) {
    let market_key = get_coin_info<T>();

    accrue_internal(borrow_mut_market_data(&mut itoken_storage.market_data, market_key), interest_rate_model_storage, dinero_storage, market_key, ctx);

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
    let market_data = borrow_mut_market_data(&mut itoken_storage.market_data, get_coin_info<T>());
    market_data.reserve_factor = reserve_factor;
  }

  entry public fun create_market<T>(
    _: &ITokenAdminCap, 
    itoken_storage: &mut ITokenStorage,
    account_storage: &mut AccountStorage, 
    borrow_cap: u64,
    ltv: u64,
    penalty_fee: u64,
    protocol_percentage: u64,
    ctx: &mut TxContext
    ) {
    let key = get_coin_info<T>();
    
    // Add the market data
    table::add(
      &mut itoken_storage.market_data, 
      key,
      MarketData {
        id: object::new(ctx),
        total_reserves: 0,
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
      &mut itoken_storage.market_tokens, 
      key,
      MarketTokens {
        balance: balance::zero<T>(),
        supply: balance::create_supply(IToken<T> {}),
    });  

    // Add bag to store address -> account
    table::add(
      &mut account_storage.accounts,
      key,
      table::new(ctx)
    );  
  }

  entry public fun pause_market<T>(_: &ITokenAdminCap, itoken_storage: &mut ITokenStorage) {
    let market_data = borrow_mut_market_data(&mut itoken_storage.market_data, get_coin_info<T>());
    market_data.is_paused = true;
  }

  entry public fun unpause_market<T>(_: &ITokenAdminCap, itoken_storage: &mut ITokenStorage) {
    let market_data = borrow_mut_market_data(&mut itoken_storage.market_data, get_coin_info<T>());
    market_data.is_paused = false;
  }

  entry public fun set_borrow_cap<T>(
    _: &ITokenAdminCap, 
    itoken_storage: &mut ITokenStorage,
    borrow_cap: u64
    ) {
    let market_data = borrow_mut_market_data(&mut itoken_storage.market_data, get_coin_info<T>());
     
     market_data.borrow_cap = borrow_cap;
  }

  entry public fun update_reserve_factor<T>(
    _: &ITokenAdminCap, 
    itoken_storage: &mut ITokenStorage,
    interest_rate_model_storage: &InterestRateModelStorage,
    dinero_storage: &DineroStorage,
    new_reserve_factor: u64,
    ctx: &mut TxContext
  ) {
    let market_key = get_coin_info<T>();
    let market_data = borrow_mut_market_data(&mut itoken_storage.market_data, market_key);
    accrue_internal(market_data, interest_rate_model_storage, dinero_storage, market_key, ctx);

    market_data.reserve_factor = new_reserve_factor;
  }

  entry public fun withdraw_reserves<T>(
    _: &ITokenAdminCap, 
    itoken_storage: &mut ITokenStorage,
    interest_rate_model_storage: &InterestRateModelStorage,
    dinero_storage: &DineroStorage,
    withdraw_value: u64,
    ctx: &mut TxContext
  ) {
    let market_key = get_coin_info<T>();
    let market_data = borrow_mut_market_data(&mut itoken_storage.market_data, market_key);
    accrue_internal(market_data, interest_rate_model_storage, dinero_storage, market_key, ctx);

    assert!(withdraw_value >= market_data.balance_value, ERROR_NOT_ENOUGH_CASH_TO_WITHDRAW);
    assert!(withdraw_value >= market_data.total_reserves, ERROR_NOT_ENOUGH_RESERVES);

    transfer::transfer(
      coin::take<T>(&mut borrow_mut_market_tokens<T>(&mut itoken_storage.market_tokens, market_key).balance, withdraw_value, ctx),
      tx_context::sender(ctx));
  }

  entry public fun update_ltv<T>(
    _: &ITokenAdminCap, 
    itoken_storage: &mut ITokenStorage,
    interest_rate_model_storage: &InterestRateModelStorage,
    dinero_storage: &DineroStorage,
    new_ltv: u64,
    ctx: &mut TxContext
  ) {
    let market_key = get_coin_info<T>();
    let market_data = borrow_mut_market_data(&mut itoken_storage.market_data, market_key);
    accrue_internal(market_data, interest_rate_model_storage, dinero_storage, market_key, ctx);

    market_data.ltv = new_ltv;
  }

  entry public fun update_dnr_interest_rate_per_epoch(_: &ITokenAdminCap, dinero_storage: &mut DineroStorage, new_interest_rate_per_epoch: u64) {
    dnr::update_interest_rate_per_epoch(dinero_storage, new_interest_rate_per_epoch)
  }

  // DNR operations

    public fun borrow_dnr(
    itoken_storage: &mut ITokenStorage, 
    account_storage: &mut AccountStorage, 
    interest_rate_model_storage: &mut InterestRateModelStorage,
    dinero_storage: &mut DineroStorage,
    oracle_storage: &OracleStorage,
    borrow_value: u64,
    ctx: &mut TxContext
  ): Coin<DNR> {
    let market_key = get_coin_info<DNR>();
    let market_data = borrow_mut_market_data(&mut itoken_storage.market_data, market_key);

    accrue_internal(market_data, interest_rate_model_storage, dinero_storage, market_key, ctx);

    let sender = tx_context::sender(ctx);

    init_account(account_storage, sender, market_key, ctx);

    init_markets_in(account_storage, sender);

    let account = borrow_mut_account(account_storage, sender, market_key);

    let new_borrow_balance = calculate_borrow_balance_of(account, market_data.borrow_index) + borrow_value;

    account.principal = (new_borrow_balance as u256);
    account.borrow_index = market_data.borrow_index;
    market_data.total_borrows = market_data.total_borrows + borrow_value;

    // Check should be the last action after all mutations
    assert!(borrow_allowed(
      &mut itoken_storage.market_data, 
      account_storage, 
      oracle_storage, 
      interest_rate_model_storage, 
      dinero_storage, 
      market_key, 
      sender, 
      borrow_value, 
      ctx), 
    ERROR_BORROW_NOT_ALLOWED);

    dnr::mint(dinero_storage, borrow_value, ctx)
  }

  public fun repay_dnr(
    itoken_storage: &mut ITokenStorage, 
    account_storage: &mut AccountStorage, 
    interest_rate_model_storage: &mut InterestRateModelStorage,
    dinero_storage: &mut DineroStorage,
    asset: Coin<DNR>,
    ctx: &mut TxContext    
  ) {
    let market_key = get_coin_info<DNR>();
    let market_data = borrow_mut_market_data(&mut itoken_storage.market_data, market_key);

    accrue_internal(market_data, interest_rate_model_storage, dinero_storage, market_key, ctx);
    
    let sender = tx_context::sender(ctx);

    let account = borrow_mut_account(account_storage, sender, market_key);

    let asset_value = coin::value(&asset);

    let repay_amount = if (asset_value > (account.principal as u64)) { (account.principal as u64) } else { asset_value };

    if (asset_value > repay_amount) pay::split_and_transfer(&mut asset, asset_value - repay_amount, sender, ctx);

    account.principal = account.principal - (repay_amount as u256);
    account.borrow_index = market_data.borrow_index;
    market_data.total_borrows = market_data.total_borrows - repay_amount;
    assert!(repay_allowed(market_data),ERROR_REPAY_NOT_ALLOWED);
    dnr::burn(dinero_storage, asset);
  }

  public fun liquidate<C, L>(
    itoken_storage: &mut ITokenStorage, 
    account_storage: &mut AccountStorage, 
    interest_rate_model_storage: &mut InterestRateModelStorage,
    dinero_storage: &mut DineroStorage,
    oracle_storage: &OracleStorage,
    asset: Coin<L>,
    borrower: address,
    ctx: &mut TxContext
  ) {
    let collateral_market_key = get_coin_info<C>();
    let loan_market_key = get_coin_info<L>();
    let dnr_market_key = get_coin_info<DNR>();
    let liquidator_address = tx_context::sender(ctx);

    let liquidation = table::borrow(&itoken_storage.liquidation, collateral_market_key);

    let penalty_fee = liquidation.penalty_fee;
    let protocol_fee = liquidation.protocol_percentage;

    assert!(liquidator_address != borrower, ERROR_LIQUIDATOR_IS_BORROWER);
    assert!(collateral_market_key != dnr_market_key, ERROR_DNR_OPERAtiON_NOT_ALLOWED);

    accrue_internal(borrow_mut_market_data(&mut itoken_storage.market_data, collateral_market_key), interest_rate_model_storage, dinero_storage, collateral_market_key, ctx);
    accrue_internal(borrow_mut_market_data(&mut itoken_storage.market_data, loan_market_key), interest_rate_model_storage, dinero_storage, loan_market_key, ctx);

    assert!(account_exists(account_storage, borrower, collateral_market_key), ERROR_ACCOUNT_COLLATERAL_DOES_EXIST);
    assert!(account_exists(account_storage, borrower, loan_market_key), ERROR_ACCOUNT_LOAN_DOES_EXIST);

    init_account(account_storage, liquidator_address, collateral_market_key, ctx);
    
    assert!(!is_user_solvent(
      &mut itoken_storage.market_data, 
      account_storage, 
      oracle_storage, 
      interest_rate_model_storage, 
      dinero_storage, 
      collateral_market_key, 
      borrower, 
      0, 
      0, 
      ctx), 
    ERROR_USER_IS_SOLVENT);

    let borrower_loan_account = borrow_mut_account(account_storage, borrower, loan_market_key);
    let borrower_loan_amount = calculate_borrow_balance_of(borrower_loan_account, borrow_market_data(&itoken_storage.market_data, loan_market_key).borrow_index);

    let asset_value = coin::value(&asset);

    let repay_max_amount = if (asset_value > borrower_loan_amount) { borrower_loan_amount } else { asset_value };

    assert!(repay_max_amount != 0, ERROR_ZERO_LIQUIDATION_AMOUNT);

    if (asset_value > repay_max_amount) pay::split_and_transfer(&mut asset, asset_value - repay_max_amount, liquidator_address, ctx);

    balance::join(&mut borrow_mut_market_tokens<L>(&mut itoken_storage.market_tokens, loan_market_key).balance, coin::into_balance(asset));

    let loan_market_data = borrow_mut_market_data(&mut itoken_storage.market_data, loan_market_key);

    if (dnr_market_key != loan_market_key) loan_market_data.balance_value = loan_market_data.balance_value + repay_max_amount;

    loan_market_data.total_borrows = loan_market_data.total_borrows - repay_max_amount;
    borrower_loan_account.principal = borrower_loan_account.principal - (repay_max_amount as u256);
    borrower_loan_account.borrow_index = loan_market_data.borrow_index;


    let collateral_price_normalized = get_price(oracle_storage, collateral_market_key);
    let loan_price_normalized = get_price(oracle_storage, loan_market_key);

    let collateral_seize_amount = fdiv(fmul(loan_price_normalized, repay_max_amount), collateral_price_normalized); 
    let collateral_seize_amount_with_fee = collateral_seize_amount + fmul(collateral_seize_amount, penalty_fee);

    let protocol_amount = fmul(collateral_seize_amount_with_fee, protocol_fee);
    let liquidator_amount = collateral_seize_amount_with_fee - protocol_amount;

    let borrower_collateral_account = borrow_mut_account(account_storage, borrower, collateral_market_key);
    borrower_collateral_account.balance_value = borrower_collateral_account.balance_value - collateral_seize_amount_with_fee;

    let liquidator_collateral_account = borrow_mut_account(account_storage, liquidator_address, collateral_market_key);
    liquidator_collateral_account.balance_value = liquidator_collateral_account.balance_value + liquidator_amount;

    let collateral_market_data = borrow_mut_market_data(&mut itoken_storage.market_data, collateral_market_key);
    collateral_market_data.total_reserves = collateral_market_data.total_reserves + protocol_amount;
  }

  // Controller

  fun deposit_allowed(market_data: &MarketData): bool {
    assert!(!market_data.is_paused, ERROR_MARKET_IS_PAUSED);
    true
  }

  fun withdraw_allowed(
    market_table: &mut Table<String, MarketData>, 
    account_storage: &mut AccountStorage, 
    oracle_storage: &OracleStorage,
    interest_rate_model_storage: &InterestRateModelStorage,
    dinero_storage: &DineroStorage,
    market_key: String,
    user: address, 
    coin_value: u64,
    ctx: &mut TxContext
  ): bool {
    assert!(!borrow_market_data(market_table, market_key).is_paused, ERROR_MARKET_IS_PAUSED);

    if (!table::contains(&account_storage.markets_in, user)) return true;

    let user_markets_in = borrow_user_markets_in(&account_storage.markets_in, user);

    if (!vector::contains(user_markets_in, &market_key)) return true;

    is_user_solvent(market_table, account_storage, oracle_storage, interest_rate_model_storage, dinero_storage, market_key, user, coin_value, 0, ctx)
  }

  fun borrow_allowed(
    market_table: &mut Table<String, MarketData>, 
    account_storage: &mut AccountStorage, 
    oracle_storage: &OracleStorage,
    interest_rate_model_storage: &InterestRateModelStorage,
    dinero_storage: &DineroStorage,
    market_key: String,
    user: address, 
    coin_value: u64,
    ctx: &mut TxContext
    ): bool {
      let current_market_data = borrow_market_data(market_table, market_key);

      assert!(!current_market_data.is_paused, ERROR_MARKET_IS_PAUSED);

      let user_markets_in = borrow_mut_user_markets_in(&mut account_storage.markets_in, user);

      if (!vector::contains(user_markets_in, &market_key)) { 
        vector::push_back(user_markets_in, market_key);
      };

      assert!(current_market_data.borrow_cap >= current_market_data.total_borrows, ERROR_BORROW_CAP_LIMIT_REACHED);
      is_user_solvent(market_table, account_storage, oracle_storage, interest_rate_model_storage, dinero_storage, market_key, user, 0, coin_value, ctx)
  }

  fun repay_allowed(market_data: &MarketData): bool {
    assert!(!market_data.is_paused, ERROR_MARKET_IS_PAUSED);
    true
  }

  fun is_user_solvent(
    market_table: &mut Table<String, MarketData>, 
    account_storage: &mut AccountStorage, 
    oracle_storage: &OracleStorage,
    interest_rate_model_storage: &InterestRateModelStorage,
    dinero_storage: &DineroStorage,
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

      let account = table::borrow(table::borrow(&account_storage.accounts, key), user);
      let market_data = borrow_mut_market_data(market_table, key);
      let (_collateral_balance, _borrow_balance) = get_account_balances_internal(market_data, account, interest_rate_model_storage, dinero_storage, key, ctx);

      let collateral_balance = if (is_modified_market) { _collateral_balance - withdraw_coin_value } else { _collateral_balance };
      let borrow_balance = if (is_modified_market) { _borrow_balance + borrow_coin_value } else { _borrow_balance };

      let price_normalized = get_price(oracle_storage, key);

      assert!(price_normalized > 0, ERROR_ZERO_ORACLE_PRICE);

      total_collateral_in_usd = total_collateral_in_usd + fmul(fmul(collateral_balance, price_normalized), market_data.ltv);
      total_borrows_in_usd = total_borrows_in_usd + fmul(borrow_balance, price_normalized);

      index = index + 1;
    };

    table::remove(&mut account_storage.markets_in, user);
    table::add(&mut account_storage.markets_in, user, markets_in_copy);

    total_collateral_in_usd > total_borrows_in_usd
  }
}