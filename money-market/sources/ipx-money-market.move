module money_market::ipx_money_market {

  use std::ascii::{String};
  use std::vector;

  use sui::tx_context::{Self, TxContext};
  use sui::object::{Self, UID, ID};
  use sui::vec_map::{Self, VecMap};
  use sui::bag::{Self, Bag};
  use sui::table::{Self, Table};
  use sui::object_table::{Self, ObjectTable};
  use sui::balance::{Self, Balance};
  use sui::coin::{Self, Coin, CoinMetadata};
  use sui::event::{emit};
  use sui::clock::{Self, Clock};
  use sui::package::{Self, Publisher};
  use sui::math;
  use sui::transfer;

  use money_market::interest_rate_model::{Self, InterestRateModelStorage};
  
  use oracle::ipx_oracle::{read_price, Price as PricePotato};

  use ipx::ipx::{Self, IPX, IPXStorage};
  
  use sui_dollar::suid::{Self, SUID, SuiDollarStorage};

  use library::utils::{get_type_name_string, get_ms_per_year};
  use library::rebase::{Self, Rebase};
  use library::math::{d_fmul, d_fdiv_u256, d_fmul_u256, double_scalar};

  const INITIAL_RESERVE_FACTOR_MANTISSA: u256 = 200000000000000000; // 0.2e18 or 20%
  const INITIAL_IPX_PER_MS: u64 = 1268391; // 40M IPX per year
  const TWENTY_FIVE_PER_CENT: u256 = 250000000000000000; // 0.25e18 or 25%
  const INITIAL_SUID_INTEREST_RATE_PER_YEAR: u64 = 20000000000000000; // 2% a year
  const MAX_SUID_INTEREST_RATE_PER_YEAR: u64 = 200000000000000000; // 20% a year

  const ERROR_NOT_ENOUGH_CASH_TO_WITHDRAW: u64 = 1;
  const ERROR_NOT_ENOUGH_CASH_TO_LEND: u64 = 2;
  const ERROR_VALUE_TOO_HIGH: u64 = 3;
  const ERROR_NOT_ENOUGH_SHARES_IN_THE_ACCOUNT: u64 = 4;
  const ERROR_NO_ADDRESS_ZERO: u64 = 5;
  const ERROR_MARKET_IS_PAUSED: u64 = 6;
  const ERROR_MARKET_NOT_UP_TO_DATE: u64 = 7;
  const ERROR_BORROW_CAP_LIMIT_REACHED: u64 = 8;
  const ERROR_ZERO_ORACLE_PRICE: u64 = 9;
  const ERROR_MARKET_EXIT_LOAN_OPEN: u64 = 10;
  const ERROR_USER_IS_INSOLVENT: u64 = 11;
  const ERROR_NOT_ENOUGH_RESERVES: u64 = 12;
  const ERROR_CAN_NOT_USE_SUID: u64 = 13;
  const ERROR_SUID_OPERATION_NOT_ALLOWED: u64 = 14;
  const ERROR_USER_IS_SOLVENT: u64 = 15;
  const ERROR_ACCOUNT_COLLATERAL_DOES_EXIST: u64 = 16;
  const ERROR_ACCOUNT_LOAN_DOES_EXIST: u64 = 17;
  const ERROR_ZERO_LIQUIDATION_AMOUNT: u64 = 18;
  const ERROR_LIQUIDATOR_IS_BORROWER: u64 = 19;
  const ERROR_MAX_COLLATERAL_REACHED: u64 = 20;
  const ERROR_CAN_NOT_BE_COLLATERAL: u64 = 21;
  const ERROR_INTEREST_RATE_OUT_OF_BOUNDS: u64 = 22;

  // OTW
  struct IPX_MONEY_MARKET has drop {}

  struct MoneyMarketAdminCap has key {
    id: UID
  }

  struct Market has key, store {
    id: UID,
    total_reserves: u64,
    accrued_timestamp: u64,
    borrow_cap: u64,
    collateral_cap: u64,
    balance_value: u64, // cash
    is_paused: bool,
    can_be_collateral: bool,
    ltv: u256,
    reserve_factor: u256,
    allocation_points: u256,
    accrued_collateral_rewards_per_share: u256,
    accrued_loan_rewards_per_share: u256,
    collateral_rebase: Rebase,
    loan_rebase: Rebase,
    decimals_factor: u64
  }

  struct MarketBalance<phantom T> has store {
    balance: Balance<T>
  }

  struct Liquidation has store {
    penalty_fee: u256,
    protocol_percentage: u256
  }

  struct MoneyMarketStorage has key {
    id: UID,
    market_data_table: ObjectTable<String, Market>,
    liquidation_table: Table<String, Liquidation>,
    accounts_table: ObjectTable<String, ObjectTable<address, Account>>, // get_coin_info -> address -> Account
    markets_in_table: Table<address, vector<String>>,  
    all_markets_keys: vector<String>,
    market_balance_bag: Bag, // get_coin_info -> MarketBalance,
    total_allocation_points: u256,
    ipx_per_ms: u64,
    suid_interest_rate_per_ms: u64,
    publisher: Publisher
  }

  struct Account has key, store {
    id: UID,
    principal: u64,
    shares: u64,
    collateral_rewards_paid: u256,
    loan_rewards_paid: u256
  }

  struct CoinPrice has store, drop {
    value: u256
  }

  // Events

  struct Deposit<phantom T> has copy, drop {
    shares: u64,
    value: u64,
    pending_rewards: u256,
    sender: address
  }

  struct Withdraw<phantom T> has copy, drop {
    shares: u64,
    value: u64,
    pending_rewards: u256,
    sender: address
  }

  struct Borrow<phantom T> has copy, drop {
    principal: u64,
    value: u64,
    pending_rewards: u256,
    sender: address
  }

  struct Repay<phantom T> has copy, drop {
    principal: u64,
    value: u64,
    pending_rewards: u256,
    sender: address
  }

  struct EnterMarket<phantom T> has copy, drop {
    sender: address
  }

  struct ExitMarket<phantom T> has copy, drop {
    sender: address
  }

  struct SetInterestRate<phantom T> has copy, drop {
    base_rate_per_year: u256,
    multiplier_per_year: u256,
    jump_multiplier_per_year: u256,
    kink: u256,
  }

  struct UpdateLiquidation<phantom T> has copy, drop {
    penalty_fee: u256,
    protocol_percentage: u256
  }

  struct CreateMarket<phantom T> has copy, drop {
    borrow_cap: u64,
    collateral_cap: u64,
    ltv: u256,
    reserve_factor: u256,
    allocation_points: u256,
    decimals_factor: u64
  }

  struct Paused<phantom T> has copy, drop {}

  struct UnPaused<phantom T> has copy, drop {}

  struct SetBorrowCap<phantom T> has copy, drop {
    borrow_cap: u64
  }

  struct UpdateReserveFactor<phantom T> has copy, drop {
    reserve_factor: u256
  }

  struct WithdrawReserves<phantom T> has copy, drop {
    value: u64
  }

  struct UpdateLTV<phantom T> has copy, drop {
    ltv: u256
  }

  struct UpdateAllocationPoints<phantom T> has copy, drop {
    allocation_points: u256
  }

  struct UpdateIPXPerMS has copy, drop {
    ipx_per_ms: u64
  }

  struct NewAdmin has copy, drop {
    admin: address
  }

  struct GetRewards<phantom T> has copy, drop {
    rewards: u256,
    sender: address
  }

  struct CanBeCollateral<phantom T> has copy, drop {
    state: bool
  }

  struct GetAllRewards has copy, drop {
    rewards: u256,
    sender: address
  }

  struct Liquidate<phantom C, phantom L> has copy, drop {
    principal_repaid: u64,
    liquidator_amount: u256,
    protocol_amount: u256,
    collateral_seized: u256,
    borrower: address,
    liquidator: address
  }

  struct UpdateSUIDInterestRate has drop, copy {
    old_value: u64,
    new_value: u64
  }

  fun init(witness: IPX_MONEY_MARKET, ctx: &mut TxContext) {
    transfer::transfer(
      MoneyMarketAdminCap {
        id: object::new(ctx)
      },
      tx_context::sender(ctx)
    );

    transfer::share_object(
      MoneyMarketStorage {
        id: object::new(ctx),
        market_data_table: object_table::new(ctx),
        liquidation_table: table::new(ctx),
        all_markets_keys: vector::empty(),
        market_balance_bag: bag::new(ctx),
        accounts_table: object_table::new(ctx),
        markets_in_table: table::new(ctx),
        total_allocation_points: 0,
        ipx_per_ms: INITIAL_IPX_PER_MS,
        suid_interest_rate_per_ms: INITIAL_SUID_INTEREST_RATE_PER_YEAR / get_ms_per_year(),
        publisher: package::claim<IPX_MONEY_MARKET>(witness, ctx)
      }
    );
  }

  /**
  * @notice It updates the loan and rewards information for the Market with collateral Coin<T> to the latest Clock timestamp.
  * @param money_market_storage The shared storage object of this module 
  * @param interest_rate_model_storage The shared storage object of money_market::interest_rate_model
  * @param clock_object The shard Clock object @0x6
  */
  public fun accrue<T>(
    money_market_storage: &mut MoneyMarketStorage, 
    interest_rate_model_storage: &InterestRateModelStorage, 
    clock_object: &Clock
    ) {
    // Save storage information before mutation
    let market_key = get_type_name_string<T>(); // Key of the current market being updated

    accrue_internal(
      borrow_mut_market_data(&mut money_market_storage.market_data_table, market_key), 
      interest_rate_model_storage, 
      clock_object,
      market_key, 
      money_market_storage.ipx_per_ms,
      money_market_storage.total_allocation_points
    );
  }

  /**
  * @notice It updates the loan information for the SUID Market
  * @param money_market_storage The shared storage object of this module 
  * @param clock_object The shard Clock object @0x6
  */
  public fun accrue_suid(
    money_market_storage: &mut MoneyMarketStorage, 
    clock_object: &Clock
  ) {
    accrue_internal_suid(
      borrow_mut_market_data(&mut money_market_storage.market_data_table, get_type_name_string<SUID>()), 
      clock_object,
      money_market_storage.suid_interest_rate_per_ms,
      money_market_storage.ipx_per_ms,
      money_market_storage.total_allocation_points
    );
  }

  /**
  * @notice It allows a user to deposit Coin<T> in a market as collateral. Other users can borrow this coin. Users can use this deposit as collateral to borrow coins from other markets. 
  * @param money_market_storage The shared storage object of this module 
  * @param interest_rate_model_storage The shared storage object of money_market::interest_rate_model
  * @param ipx_storage The shared object of the module ipx::ipx 
  * @param clock_object The shard Clock object @0x6
  * @param asset The Coin<T> the user is depositing
  * @return Coin<IPX> It will mint IPX rewards to the user.
  * Requirements: 
  * - The market is not paused
  * - The collateral cap has not been reached
  */
  public fun deposit<T>(
    money_market_storage: &mut MoneyMarketStorage, 
    interest_rate_model_storage: &InterestRateModelStorage,
    ipx_storage: &mut IPXStorage, 
    clock_object: &Clock,
    asset: Coin<T>,
    ctx: &mut TxContext
  ): Coin<IPX> {
      // Get the type name of the Coin<T> of this market.
      let market_key = get_type_name_string<T>();
      // User cannot use SUID as collateral
      assert!(market_key != get_type_name_string<SUID>(), ERROR_SUID_OPERATION_NOT_ALLOWED);
      
      // Get market core information
      let market_data = borrow_mut_market_data(&mut money_market_storage.market_data_table, market_key);
      let market_balance = borrow_mut_market_balance<T>(&mut money_market_storage.market_balance_bag, market_key);

      // Save the sender address in memory
      let sender = tx_context::sender(ctx);

      // We need to register his account on the first deposit call, if it does not exist.
      init_account(&mut money_market_storage.accounts_table, sender, market_key, ctx);

      // We need to update the market loan and rewards before accepting a deposit
      accrue_internal(
        market_data, 
        interest_rate_model_storage, 
        clock_object,
        market_key, 
        money_market_storage.ipx_per_ms,
         money_market_storage.total_allocation_points
      );

      // Declare the pending rewards variable that will save the value of Coin<IPX> to mint.
      let pending_rewards = 0;

      // Get the caller Account to update
      let account = borrow_mut_account(&mut money_market_storage.accounts_table, sender, market_key);

      // If the sender has shares already, we need to calculate his rewards before this deposit.
      if (account.shares > 0) 
        // Math: we need to remove the decimals of shares during fixed point multiplication to maintain IPX decimal houses
        pending_rewards = (
          ((account.shares as u256) * 
          market_data.accrued_collateral_rewards_per_share) / 
          (market_data.decimals_factor as u256)) - 
          account.collateral_rewards_paid;
      
      // Save the value of the coin being deposited in memory
      let asset_value = coin::value(&asset);

      // Update the collateral rebase. 
      // We round down to give the edge to the protocol
      let shares = rebase::add_elastic(&mut market_data.collateral_rebase, asset_value, false);

      // Deposit the Coin<T> in the market
      balance::join(&mut market_balance.balance, coin::into_balance(asset));
      // Update the amount of cash in the market
      market_data.balance_value = market_data.balance_value + asset_value;

      // Assign the additional shares to the sender
      account.shares = account.shares + shares;
      // Consider all rewards earned by the sender paid
      account.collateral_rewards_paid = ((account.shares as u256) * market_data.accrued_collateral_rewards_per_share) / (market_data.decimals_factor as u256);

      // Defense hook after all mutations
      deposit_allowed(market_data);

      emit(
        Deposit<T> {
          shares,
          value: asset_value,
          pending_rewards,
          sender
        }
      );

      // Mint Coin<IPX> to the user.
      mint_ipx(money_market_storage, ipx_storage, pending_rewards, ctx)
  }  

  /**
  * @notice It allows a user to withdraw his shares of Coin<T>.  
  * @param money_market_storage The shared storage of this module
  * @param interest_rate_model_storage The shared storage object of money_market::interest_rate_model
  * @param ipx_storage The shared object of the module ipx::ipx 
  * @param price_potatoes A vector of PricePotato potatoes from the Oracle
  * @param clock_object The shared Clock object
  * @param shares_to_remove The number of shares the user wishes to remove
  * @return (Coin<T>, Coin<IPX>)
  * Requirements: 
  * - Market is not paused 
  * - User is solvent after withdrawing Coin<T> collateral
  */
  public fun withdraw<T>(
    money_market_storage: &mut MoneyMarketStorage, 
    interest_rate_model_storage: &InterestRateModelStorage,
    ipx_storage: &mut IPXStorage, 
    price_potatoes: vector<PricePotato>,
    clock_object: &Clock,
    shares_to_remove: u64,
    ctx: &mut TxContext
  ): (Coin<T>, Coin<IPX>) {
    // Get the type name of the Coin<T> of this market.
    let market_key = get_type_name_string<T>();
    // User cannot use SUID as collateral
    assert!(market_key != get_type_name_string<SUID>(), ERROR_SUID_OPERATION_NOT_ALLOWED);
      
    // Get market core information
    let market_data = borrow_mut_market_data(&mut money_market_storage.market_data_table, market_key);
    let market_balance = borrow_mut_market_balance<T>(&mut money_market_storage.market_balance_bag, market_key);

    // Update the market rewards & loans before any mutations
    accrue_internal(
      market_data, 
      interest_rate_model_storage, 
      clock_object,
      market_key, 
      money_market_storage.ipx_per_ms,
      money_market_storage.total_allocation_points
    );

    // Save the sender info in memory
    let sender = tx_context::sender(ctx);

    // Get the sender account struct
    let account = borrow_mut_account(&mut money_market_storage.accounts_table, sender, market_key);
    // No point to proceed if the sender does not have any shares to withdraw.
    assert!(account.shares >= shares_to_remove, ERROR_NOT_ENOUGH_SHARES_IN_THE_ACCOUNT);
    
    // Math: we need to remove the decimals of shares during fixed point multiplication to maintain IPX decimal houses
    let pending_rewards = ((account.shares as u256) * 
          market_data.accrued_collateral_rewards_per_share / 
          (market_data.decimals_factor as u256)) - 
          account.collateral_rewards_paid;
    
    // Update the base and elastic of the collateral rebase
    // Round down to give the edge to the protocol
    let underlying_to_redeem = rebase::sub_base(&mut market_data.collateral_rebase, shares_to_remove, false);

    // Market must have enough cash or there is no point to proceed
    assert!(market_data.balance_value >= underlying_to_redeem , ERROR_NOT_ENOUGH_CASH_TO_WITHDRAW);

    // Reduce the amount of cash in the market
    market_data.balance_value = market_data.balance_value - underlying_to_redeem;

    // Remove the shares from the sender
    account.shares = account.shares - shares_to_remove;
    // Consider all rewards earned by the sender paid
    account.collateral_rewards_paid = (account.shares as u256) * market_data.accrued_collateral_rewards_per_share / (market_data.decimals_factor as u256);

    // Remove Coin<T> from the market
    let underlying_coin = coin::take(&mut market_balance.balance, underlying_to_redeem, ctx);

    let price_map = get_price(price_potatoes);

     // Defense hook after all mutations
    withdraw_allowed(
      money_market_storage, 
      &price_map, 
      interest_rate_model_storage, 
      clock_object,
      market_key, 
      sender
     );

    emit(
        Withdraw<T> {
          shares: shares_to_remove,
          value: underlying_to_redeem,
          pending_rewards,
          sender
        }
    );


    // Return Coin<T> and Coin<IPX> to the sender
    (underlying_coin, mint_ipx(money_market_storage, ipx_storage, pending_rewards, ctx))
  }

  /**
  * @notice It allows a user to borrow Coin<T>.  
  * @param money_market_storage The shared storage of this module 
  * @param interest_rate_model_storage The shared storage object of money_market::interest_rate_model
  * @param ipx_storage The shared object of the module ipx::ipx 
  * @param price_potatoes A Vector of price potatoes from the Oracle
  * @param clock_object The shared Clock object
  * @param borrow_value The value of Coin<T> the user wishes to borrow
  * @return (Coin<T>, Coin<IPX>)
  * Requirements: 
  * - Market is not paused 
  * - User is solvent after borrowing Coin<T> collateral
  * - Market borrow cap has not been reached
  */
  public fun borrow<T>(
    money_market_storage: &mut MoneyMarketStorage, 
    interest_rate_model_storage: &InterestRateModelStorage,
    ipx_storage: &mut IPXStorage, 
    price_potatoes: vector<PricePotato> ,
    clock_object: &Clock,
    borrow_value: u64,
    ctx: &mut TxContext
  ): (Coin<T>, Coin<IPX>) {
    // Get the type name of the Coin<T> of this market.
    let market_key = get_type_name_string<T>();
    let suid_market_key = get_type_name_string<SUID>();
    // User cannot use SUID as collateral
    assert!(market_key != suid_market_key, ERROR_SUID_OPERATION_NOT_ALLOWED);
      
    // Get market core information
    let market_data = borrow_mut_market_data(&mut money_market_storage.market_data_table, market_key);
    let market_balance = borrow_mut_market_balance<T>(&mut money_market_storage.market_balance_bag, market_key);

    // There is no point to proceed if the market does not have enough cash
    assert!(market_data.balance_value >= borrow_value, ERROR_NOT_ENOUGH_CASH_TO_LEND);

    // Update the market rewards & loans before any mutations
    accrue_internal(
      market_data, 
      interest_rate_model_storage, 
      clock_object,
      market_key, 
      money_market_storage.ipx_per_ms,
      money_market_storage.total_allocation_points
    );

    // Save the sender address in memory
    let sender = tx_context::sender(ctx);

    // Init the account if the user never borrowed or deposited in this market
    init_account(&mut money_market_storage.accounts_table, sender, market_key, ctx);

    // Register market in vector if the user never entered any market before
    init_markets_in(&mut money_market_storage.markets_in_table, sender);

    // Get the user account
    let account = borrow_mut_account(&mut money_market_storage.accounts_table, sender, market_key);

    let pending_rewards = 0;
    // If the sender has a loan already, we need to calculate his rewards before this loan.
    if (account.principal > 0) 
      // Math: we need to remove the decimals of shares during fixed point multiplication to maintain IPX decimal houses
      pending_rewards = (
        (account.principal as u256) * 
        market_data.accrued_loan_rewards_per_share / 
        (market_data.decimals_factor as u256)) - 
        account.loan_rewards_paid;

    // Update the loan rebase with the new loan
    let borrow_principal = rebase::add_elastic(&mut market_data.loan_rebase, borrow_value, true);

    // Update the principal owed by the sender
    account.principal = account.principal + borrow_principal; 
    // Consider all rewards paid
    account.loan_rewards_paid = (account.principal as u256) * market_data.accrued_loan_rewards_per_share / (market_data.decimals_factor as u256);
    // Consider all rewards paid
    market_data.balance_value = market_data.balance_value - borrow_value;

    // Remove Coin<T> from the market
    let loan_coin = coin::take(&mut market_balance.balance, borrow_value, ctx);

    // Check should be the last action after all mutations
    borrow_allowed(
      money_market_storage, 
      &get_price(price_potatoes), 
      interest_rate_model_storage, 
      clock_object,
      market_key, 
      sender
    );

    emit(
      Borrow<T> {
        principal: borrow_principal,
        value: borrow_value,
        pending_rewards,
        sender
      }
    );

    (loan_coin, mint_ipx(money_market_storage, ipx_storage, pending_rewards, ctx))
  }

  /**
  * @notice It allows a user to repay his principal with Coin<T>.  
  * @param money_market_storage The shared storage of this module 
  * @param interest_rate_model_storage The shared storage object of money_market::interest_rate_model
  * @param ipx_storage The shared object of the module ipx::ipx 
  * @param clock_object The shared Clock object
  * @param asset The Coin<T> he is repaying. 
  * @param principal_to_repay The amount of principal he wishes to repay
  * @return (Coin<T>, Coin<IPX> )rewards
  * Requirements: 
  * - Market is not paused 
  */
  public fun repay<T>(
    money_market_storage: &mut MoneyMarketStorage, 
    interest_rate_model_storage: &InterestRateModelStorage,
    ipx_storage: &mut IPXStorage, 
    clock_object: &Clock,
    asset: Coin<T>,
    principal_to_repay: u64,
    ctx: &mut TxContext
  ): (Coin<T>, Coin<IPX>) {
    // Get the type name of the Coin<T> of this market.
    let market_key = get_type_name_string<T>();
    // User cannot use SUID as collateral
    assert!(market_key != get_type_name_string<SUID>(), ERROR_SUID_OPERATION_NOT_ALLOWED);
      
    // Get market core information
    let market_data = borrow_mut_market_data(&mut money_market_storage.market_data_table, market_key);
    let market_balance = borrow_mut_market_balance<T>(&mut money_market_storage.market_balance_bag, market_key);

    // Update the market rewards & loans before any mutations
    accrue_internal(
      market_data, 
      interest_rate_model_storage, 
      clock_object,
      market_key, 
      money_market_storage.ipx_per_ms,
      money_market_storage.total_allocation_points
    );
    
    // Save the sender in memory
    let sender = tx_context::sender(ctx);

    // Get the sender's account
    let account = borrow_mut_account(&mut money_market_storage.accounts_table, sender, market_key);

    // Calculate the sender rewards before repayment
    // Math: we need to remove the decimals of shares during fixed point multiplication to maintain IPX decimal houses
    let pending_rewards = (
        (account.principal as u256) * 
        market_data.accrued_loan_rewards_per_share / 
        (market_data.decimals_factor as u256)) - 
        account.loan_rewards_paid;

    // Save the value of Coin<T> in memory
    let asset_value = coin::value(&asset);

    // Convert asset_value to principal
    let asset_principal = rebase::to_base(&market_data.loan_rebase, asset_value, false);

    // Ensure that the user is not overpaying his loan. This is important because the interest rate keeps accruing every second.
    // Users will usually send more Coin<T> then needed
    let safe_asset_principal = if (asset_principal > account.principal) { math::min(account.principal, principal_to_repay) } else { math::min(asset_principal, principal_to_repay) };

    // Convert the safe principal amount to Coin<T> value so we can send any extra back to the user
    let repay_amount = rebase::to_elastic(&market_data.loan_rebase, safe_asset_principal, true);

    // If the sender send more Coin<T> then necessary, we return the extra to him
    let extra_coin = if (asset_value > repay_amount) { coin::split(&mut asset, asset_value - repay_amount, ctx) } else { coin::zero<T>(ctx) };

    // Deposit Coin<T> in the market
    balance::join(&mut market_balance.balance, coin::into_balance(asset));
    // Increase the cash in the market
    market_data.balance_value = market_data.balance_value + repay_amount;
    // Reduce the total principal
    rebase::sub_base(&mut market_data.loan_rebase, safe_asset_principal, true);

    // Remove the principal repaid from the user account
    account.principal = account.principal - safe_asset_principal;
    // Consider all rewards paid
    account.loan_rewards_paid = (account.principal as u256) * market_data.accrued_loan_rewards_per_share / (market_data.decimals_factor as u256);
    repay_allowed(market_data);

    emit(
      Repay<T> {
        principal: safe_asset_principal,
        value: repay_amount,
        pending_rewards,
        sender
      }
    );

    (extra_coin, mint_ipx(money_market_storage, ipx_storage, pending_rewards, ctx))
  }
  
  /**
  * @notice It returns the current interest rate per ms
  * @param money_market_storage The shared storage of this module 
  * @param interest_rate_model_storage The shared storage object of money_market::interest_rate_model
  * @return interest rate per ms % for Market of Coin<T>
  */
  public fun get_borrow_rate_per_ms<T>(
    money_market_storage: &MoneyMarketStorage, 
    interest_rate_model_storage: &InterestRateModelStorage,
    ): u64 {
    let market_key = get_type_name_string<T>();
    get_borrow_rate_per_ms_internal(
      money_market_storage,
      borrow_market_data(&money_market_storage.market_data_table, market_key),
      interest_rate_model_storage,
      market_key
    )
  }

  /**
  * @notice It returns the current interest rate per ms
  * @param money_market_storage The shared storage of this module 
  * @param market_data The Market struct of Market for Coin<T>
  * @param interest_rate_model_storage The shared storage object of money_market::interest_rate_model
  * @param market_key The key of the market
  * @return interest rate per ms % for Market of Coin<T>
  */
  fun get_borrow_rate_per_ms_internal(
    money_market_storage: &MoneyMarketStorage, 
    market_data: &Market, 
    interest_rate_model_storage: &InterestRateModelStorage,
    market_key: String,
    ): u64 {
      // SUID has a constant interest_rate
      if (get_type_name_string<SUID>() == market_key) {
        money_market_storage.suid_interest_rate_per_ms
      } else {
       // Other coins follow the start jump rate interest rate model 
        interest_rate_model::get_borrow_rate_per_ms(
          interest_rate_model_storage,
          market_key,
          market_data.balance_value,
          rebase::elastic(&market_data.loan_rebase),
          market_data.total_reserves
        )
      }
  }

  /**
  * @notice It returns the current interest rate earned per ms
  * @param money_market_storage The shared storage of this module 
  * @param interest_rate_model_storage The shared storage object of money_market::interest_rate_model
  * @return interest rate earned per ms % for Market of Coin<T>
  */
  public fun get_supply_rate_per_ms<T>(
    money_market_storage: &MoneyMarketStorage, 
    interest_rate_model_storage: &InterestRateModelStorage
  ): u64 {
      let market_key = get_type_name_string<T>();
      assert!(market_key != get_type_name_string<SUID>(), ERROR_SUID_OPERATION_NOT_ALLOWED);

      let market_data = borrow_market_data(&money_market_storage.market_data_table, market_key);
      // Other coins follow the start jump rate interest rate model       
      interest_rate_model::get_supply_rate_per_ms(
          interest_rate_model_storage,
          market_key,
          market_data.balance_value,
          rebase::elastic(&market_data.loan_rebase),
          market_data.total_reserves,
          market_data.reserve_factor
        )
  }

  /**
  * @notice It allows the user to his shares in Market for Coin<T> as collateral to open loans 
  * @param money_market_storage The MoneyMarketStorage shared object of this contract
  */
  public fun enter_market<T>(money_market_storage: &mut MoneyMarketStorage, ctx: &mut TxContext) {

    // Save the market key in memory
    let market_key = get_type_name_string<T>();
   
    let market_data = borrow_market_data(&money_market_storage.market_data_table, market_key);

    assert!(market_data.can_be_collateral, ERROR_CAN_NOT_BE_COLLATERAL);

    // Save the sender address in memory
    let sender = tx_context::sender(ctx);

    // Init the markets_in account if he never interacted with this market
    init_markets_in(&mut money_market_storage.markets_in_table, sender);

   // Get the user market_in account
   let user_markets_in = borrow_mut_user_markets_in(&mut money_market_storage.markets_in_table, sender);

   // Add the market_key to the account if it is not present
   if (!vector::contains(user_markets_in, &market_key)) { 
      vector::push_back(user_markets_in, market_key);
    };

    emit(
      EnterMarket<T> {
        sender
      }
    );
  }

  /**
  * @notice It removes a market as collateral.  
  * @param money_market_storage The shared storage object of this contract
  * @param interest_rate_model_storage The shared storage object of money_market::interest_rate_model
  * @param price_potatoes a vector of PricePotato potatoes from the Oracle
  * @param clock_object The shared Clock object
  */
  public fun exit_market<T>(
    money_market_storage: &mut MoneyMarketStorage, 
    interest_rate_model_storage: &InterestRateModelStorage,
    price_potatoes: vector<PricePotato>,
    clock_object: &Clock,
    ctx: &mut TxContext
  ) {
    let market_key = get_type_name_string<T>();
    let sender = tx_context::sender(ctx);
    let account = borrow_account(&money_market_storage.accounts_table, sender, market_key);

    // Sender cannot exit a market if he is currently borrowing from it
    assert!(account.principal == 0, ERROR_MARKET_EXIT_LOAN_OPEN);
   
   // Get user markets_in account
   let user_markets_in = borrow_mut_user_markets_in(&mut money_market_storage.markets_in_table, sender);
   
   // Verify if the user is indeed registered in this market and index in the vector
   let (is_present, index) = vector::index_of(user_markets_in, &market_key);
   
  // If he is in the market we remove him.
   if (is_present) {
    let _ = vector::remove(user_markets_in, index);
   };

  // Sender must remain solvent after removing the account
  assert!(
     is_user_solvent(
      money_market_storage, 
      &get_price(price_potatoes), 
      interest_rate_model_storage, 
      clock_object,
      sender
     ), 
    ERROR_USER_IS_INSOLVENT
  );

    emit(
      ExitMarket<T> {
        sender
      }
    );
  }

  /**
  * @notice It returns a tuple containing the updated (collateral value, loan value) of a user for Market of Coin<T> 
  * @param money_market_storage The shared storage object of this contract
  * @param interest_rate_model_storage The shared storage object of money_market::interest_rate_model
  * @param clock_object The shared Clock object
  * @param user The address of the account we wish to check
  * @return (collateral value, loan value)
  */
  public fun get_account_balances<T>(
    money_market_storage: &mut MoneyMarketStorage, 
    interest_rate_model_storage: &InterestRateModelStorage, 
    clock_object: &Clock,
    user: address
   ): (u64, u64) {
    let market_key = get_type_name_string<T>();  

    // Get the market data
    let market_data = borrow_mut_market_data(&mut money_market_storage.market_data_table, market_key);
    // Get the user account
    let account = borrow_account(&money_market_storage.accounts_table, user, market_key);
    
    get_account_balances_internal(
      market_data, 
      account, 
      interest_rate_model_storage, 
      clock_object,
      market_key, 
      money_market_storage.suid_interest_rate_per_ms,
      money_market_storage.ipx_per_ms,
      money_market_storage.total_allocation_points
    )
  }

  /**
  * @notice It returns a tuple containing the updated (collateral value, loan value) of a user for Market of Coin<T> 
  * @param market_data The Market struct
  * @param account The account struct of a user
  * @param interest_rate_model_storage The shared storage object of money_market::interest_rate_model
  * @param clock_object The shared Clock object
  * @param market_key The key of the market in question
  * @param suid_interest_rate_per_ms The borrowing rate of SUID per millisecond
  * @param ipx_per_ms The value of IPX to mint per millisecond
  * @param total_allocation_points It stores all allocation points assigned to all markets
  * @return (collateral value, loan value)
  */
  fun get_account_balances_internal(
    market_data: &mut Market,
    account: &Account,
    interest_rate_model_storage: &InterestRateModelStorage,
    clock_object: &Clock,
    market_key: String, 
    suid_interest_rate_per_ms: u64,
    ipx_per_ms: u64,
    total_allocation_points: u256
  ): (u64, u64) {
    if (clock::timestamp_ms(clock_object) > market_data.accrued_timestamp) {
        if (market_key == get_type_name_string<SUID>()) {
             accrue_internal_suid(
              market_data, 
              clock_object,
              suid_interest_rate_per_ms,
              ipx_per_ms,
              total_allocation_points
            );
        } else {
          accrue_internal(
            market_data, 
            interest_rate_model_storage, 
            clock_object, 
            market_key,
            ipx_per_ms,
            total_allocation_points
          );  
        }
      };

     (
      rebase::to_elastic(&market_data.collateral_rebase, account.shares, false), 
      rebase::to_elastic(&market_data.loan_rebase, account.principal, true)
     )
  }

   /**
  * @notice It updates the Market loan and rewards information
  * @param market_data The Market struct
  * @param clock_object The shared Clock object
  * @param suid_interest_rate_per_ms The borrowing rate of SUID per millisecond
  * @param ipx_per_epoch The value of IPX to mint per millisecond
  * @param total_allocation_points It stores all allocation points assigned to all markets
  */
  fun accrue_internal_suid(
    market_data: &mut Market, 
    clock_object: &Clock,
    suid_interest_rate_per_ms: u64,
    ipx_per_ms: u64,
    total_allocation_points: u256
  ) {
    let current_timestamp_ms = clock::timestamp_ms(clock_object);
    let timestamp_ms_delta = current_timestamp_ms - market_data.accrued_timestamp;

    // If no time has passed since the last update, there is nothing to do.
    if (timestamp_ms_delta == 0) return;

    // Calculate the interest rate % accumulated for all epochs since the last update
    let interest_rate = timestamp_ms_delta * suid_interest_rate_per_ms;

    // Calculate the total interest rate amount earned by the protocol
    let interest_rate_amount = (d_fmul(interest_rate, rebase::elastic(&market_data.loan_rebase)) as u64);

    // Increase the total borrows by the interest rate amount
    rebase::increase_elastic(&mut market_data.loan_rebase, interest_rate_amount);

    // Update the accrued timestamp
    market_data.accrued_timestamp = current_timestamp_ms;

    // Update the reserves
    market_data.total_reserves = market_data.total_reserves + interest_rate_amount;

    // Total IPX rewards accumulated for all passing epochs
    let rewards = (market_data.allocation_points * (timestamp_ms_delta as u256) * (ipx_per_ms as u256)) / total_allocation_points;

    // Get the total borrow amount of the market
    let total_principal = rebase::base(&market_data.loan_rebase);

    // Avoid zero division
    if (total_principal != 0)  
      market_data.accrued_loan_rewards_per_share = market_data.accrued_loan_rewards_per_share + ((rewards * (market_data.decimals_factor as u256)) / (total_principal as u256));
  } 

  /**
  * @notice It updates the Market loan and rewards information
  * @param market_data The Market struct
  * @param interest_rate_model_storage The shared storage object of money_market::interest_rate_model
  * @param clock_object The shared Clock object
  * @param market_key The key of the market in question
  * @param ipx_per_ms The value of IPX to mint per millisecond for the entire module
  * @param total_allocation_points It stores all allocation points assigned to all markets
  */
  fun accrue_internal(
    market_data: &mut Market, 
    interest_rate_model_storage: &InterestRateModelStorage,
    clock_object: &Clock,
    market_key: String,
    ipx_per_ms: u64,
    total_allocation_points: u256, 
  ) {
    let current_timestamp_ms = clock::timestamp_ms(clock_object);
    let timestamp_ms_delta = current_timestamp_ms - market_data.accrued_timestamp;

    // If no time has passed since the last update, there is nothing to do.
    if (timestamp_ms_delta == 0) return;

    // Calculate the interest rate % accumulated per millisecond since the last update
    let interest_rate = timestamp_ms_delta * interest_rate_model::get_borrow_rate_per_ms(
          interest_rate_model_storage,
          market_key,
          market_data.balance_value,
          rebase::elastic(&market_data.loan_rebase),
          market_data.total_reserves
        );


    // Calculate the total interest rate amount earned by the protocol
    let interest_rate_amount = d_fmul(interest_rate, rebase::elastic(&market_data.loan_rebase));
    // Calculate how much interest rate will be given to the reserves
    let reserve_interest_rate_amount = d_fmul_u256(interest_rate_amount, market_data.reserve_factor);

    // Increase the total borrows by the interest rate amount
    rebase::increase_elastic(&mut market_data.loan_rebase, (interest_rate_amount as u64));
    // Increase the total amount earned 
    rebase::increase_elastic(&mut market_data.collateral_rebase, (interest_rate_amount - reserve_interest_rate_amount as u64));

    // Update the accrued timestamp
    market_data.accrued_timestamp = current_timestamp_ms;
    // Update the reserves
    market_data.total_reserves = market_data.total_reserves + (reserve_interest_rate_amount as u64);

    // Total IPX rewards accumulated since the last update
    let rewards = (market_data.allocation_points * (timestamp_ms_delta as u256) * (ipx_per_ms as u256)) / total_allocation_points;

    // Split the rewards evenly between loans and collateral
    let collateral_rewards = rewards / 2; 
    let loan_rewards = rewards - collateral_rewards;

    // Get the total shares amount of the market
    let total_shares = rebase::base(&market_data.collateral_rebase);
    // Get the total borrow amount of the market
    let total_principal = rebase::base(&market_data.loan_rebase);

    // Update the total rewards per share.

    // Avoid zero division
    if (total_shares != 0)
      market_data.accrued_collateral_rewards_per_share = market_data.accrued_collateral_rewards_per_share + ((collateral_rewards * (market_data.decimals_factor as u256)) / (total_shares as u256));

    // Avoid zero division
    if (total_principal != 0)  
      market_data.accrued_loan_rewards_per_share = market_data.accrued_loan_rewards_per_share + ((loan_rewards * (market_data.decimals_factor as u256)) / (total_principal as u256));
  } 

  /****************************************
    STORAGE GETTERS
  **********************************************/ 
  fun borrow_market_balance<T>(market_balance: &Bag, market_key: String): &MarketBalance<T> {
    bag::borrow(market_balance, market_key)
  }

  fun borrow_mut_market_balance<T>(market_balance: &mut Bag, market_key: String): &mut MarketBalance<T> {
    bag::borrow_mut(market_balance, market_key)
  }

  fun borrow_market_data(market_data: &ObjectTable<String, Market>, market_key: String): &Market {
    object_table::borrow(market_data, market_key)
  }

  fun borrow_mut_market_data(market_data: &mut ObjectTable<String, Market>, market_key: String): &mut Market {
    object_table::borrow_mut(market_data, market_key)
  }

  fun borrow_account(accounts_table: &ObjectTable<String, ObjectTable<address, Account>>, user: address, market_key: String): &Account {
    object_table::borrow(object_table::borrow(accounts_table, market_key), user)
  }

  fun borrow_mut_account(accounts_table: &mut ObjectTable<String, ObjectTable<address, Account>>, user: address, market_key: String): &mut Account {
    object_table::borrow_mut(object_table::borrow_mut(accounts_table, market_key), user)
  }

  fun borrow_user_markets_in(markets_in: &Table<address, vector<String>>, user: address): &vector<String> {
    table::borrow(markets_in, user)
  }

  fun borrow_mut_user_markets_in(markets_in: &mut Table<address, vector<String>>, user: address): &mut vector<String> {
    table::borrow_mut(markets_in, user)
  }

  fun account_exists(accounts_table: &ObjectTable<String, ObjectTable<address, Account>>, user: address, market_key: String): bool {
    object_table::contains(object_table::borrow(accounts_table, market_key), user)
  }

 /**
  * @dev It registers an empty Account for a Market with a key if it is not present
  * @param accounts_table The Account Table
  * @param user The address of the user we wish to initiate his account
  */
  fun init_account(accounts_table: &mut ObjectTable<String, ObjectTable<address, Account>>, user: address, key: String, ctx: &mut TxContext) {
    if (!account_exists(accounts_table, user, key)) {
          object_table::add(
            object_table::borrow_mut(accounts_table, key),
            user,
            Account {
              id: object::new(ctx),
              principal: 0,
              shares: 0,
              collateral_rewards_paid: 0,
              loan_rewards_paid: 0
            }
        );
    };
  }

  /**
  * @dev It registers an empty markets_in for a user 
  * @param markets_in_table The table that contains the market, which the user has allowed its deposits to be collateral
  * @param user The address of the user we wish to initiate his markets_in vector
  */
  fun init_markets_in(markets_in_table: &mut Table<address, vector<String>>, user: address) {
    if (!table::contains(markets_in_table, user)) {
      table::add(
       markets_in_table,
       user,
       vector::empty<String>()
      );
    };
  }

  /**
  * @dev A utility function to mint IPX.
  * @param ipx_storage The shared object of the module ipx::ipx 
  * @param value The value for Coin<IPX> to mint
  */
  fun mint_ipx(money_market_storage: &MoneyMarketStorage, ipx_storage: &mut IPXStorage, value: u256, ctx: &mut TxContext): Coin<IPX> {
    // We can create a Coin<IPX> with 0 value without minting
    if (value == 0) { coin::zero<IPX>(ctx) } else { ipx::mint(ipx_storage, &money_market_storage.publisher, (value as u64), ctx) }
  }

  /**
  * @dev A utility function to get a VecMap Coin Type String => Coin PricePotato average
  * @param price_vector Vector of PricePotato HotPotato
  * @return VecMap containing the prices
  */
  fun get_price(price_vector: vector<PricePotato>): VecMap<String, CoinPrice> {

    let length = vector::length(&price_vector);
    let index = 0;
    let price_map = vec_map::empty<String, CoinPrice>();

    // SUID is always a dollar
    vec_map::insert(&mut price_map, get_type_name_string<SUID>(), CoinPrice {value: double_scalar() });

    while (length > index) {

      let price_potato = vector::pop_back(&mut price_vector);

      // Fetch the price from the Oracle
      let (average, _switchboard_result, _pyth_result, _scalar, _pyth_timestamp, _switchboard_timestamp, coin_name) = read_price(price_potato);

      vec_map::insert(&mut price_map, coin_name, CoinPrice { value: average });

      index = index + 1;
    };

    vector::destroy_empty(price_vector);

    price_map
  }

  /**
  * @notice It allows the admin to update the interest rate per millisecond for Coin<T>
  * @param _ The MoneyMarketAdminCap
  * @param money_market_storage The shared storage of this module 
  * @param interest_rate_model_storage The shared storage object of money_market::interest_rate_model
  * @param clock_object The shared Clock object
  * @param base_rate_per_year The minimum rate per year
  * @param multiplier_rate_per_year The rate applied as the liquidity decreases
  * @param jump_multiplier_rate_per_year An amplified rate once the kink is passed to address low liquidity levels
  * @kink The threshold that decides when the liquidity is considered very low
  * @return (Coin<T>, Coin<IPX>)
  * Requirements: 
  * - Only the admin can call this function
  */
  entry public fun set_interest_rate_data<T>(
    _: &MoneyMarketAdminCap,
    money_market_storage: &mut MoneyMarketStorage, 
    interest_rate_model_storage: &mut InterestRateModelStorage,
    clock_object: &Clock,
    base_rate_per_year: u256,
    multiplier_per_year: u256,
    jump_multiplier_per_year: u256,
    kink: u256,
    ctx: &mut TxContext
  ) {
    let market_key = get_type_name_string<T>();
    assert!(market_key != get_type_name_string<SUID>(), ERROR_SUID_OPERATION_NOT_ALLOWED);

    let total_allocation_points = money_market_storage.total_allocation_points;
    let ipx_per_ms = money_market_storage.ipx_per_ms;

    // Update the market information before updating its interest rate
    accrue_internal(
      borrow_mut_market_data(&mut money_market_storage.market_data_table, market_key), 
      interest_rate_model_storage, 
      clock_object,
      market_key, 
      ipx_per_ms,
      total_allocation_points, 
    );

    // Update the interest rate
    interest_rate_model::set_interest_rate_data<T>(
      interest_rate_model_storage,
      base_rate_per_year,
      multiplier_per_year,
      jump_multiplier_per_year,
      kink,
      ctx
    );

    emit(
      SetInterestRate<T> {
        base_rate_per_year,
        multiplier_per_year,
        jump_multiplier_per_year,
        kink
      }
    );
  } 

  /**
  * @notice It allows the admin to update the penalty fee and protocol percentage when a user is liquidated
  * @param _ The MoneyMarketAdminCap
  * @param money_market_storage The shared storage of this module 
  * @param penalty_fee The % fee a user pays when liquidated with 18 decimals
  * @param protocol_percentage The % of the penalty fee the protocol retains with 18 decimals
  */
  entry public fun update_liquidation<T>(
    _: &MoneyMarketAdminCap, 
    money_market_storage: &mut MoneyMarketStorage, 
    penalty_fee: u256,
    protocol_percentage: u256
    ) {
    // Make sure the protocol can not seize the entire value of a position during liquidations
    assert!(TWENTY_FIVE_PER_CENT >= penalty_fee, ERROR_VALUE_TOO_HIGH);
    assert!(TWENTY_FIVE_PER_CENT >= protocol_percentage, ERROR_VALUE_TOO_HIGH);

    let liquidation = table::borrow_mut(&mut money_market_storage.liquidation_table, get_type_name_string<T>());
    liquidation.penalty_fee = penalty_fee;
    liquidation.protocol_percentage = protocol_percentage;

    emit(
      UpdateLiquidation<T> {
        penalty_fee,
        protocol_percentage,
      }
    );
  }

  /**
  * @notice It allows the to add a new market for Coin<T>.
  * @param _ The MoneyMarketAdminCap
  * @param money_market_storage The shared storage object of this module
  * @param clock_object The shared Clock object
  * @param coin_metadata The CoinMetaData<T> of Coin<T>
  * @param borrow_cap The maximum value that can be borrowed for this market 
  * @param collateral_cap The maximum amount of collateral that can be added to this market
  * @param ltv The loan to value ratio of this market 
  * @param allocation_points The % of rewards this market will get 
  * @param penalty_fee The % fee a user pays when liquidated with 9 decimals
  * @param protocol_percentage The % of the penalty fee the protocol retains with 9 decimals
  * @param can_be_collateral It indicates if this market can be used as collateral to borrow other coins
  */
  entry public fun create_market<T>(
    _: &MoneyMarketAdminCap, 
    money_market_storage: &mut MoneyMarketStorage, 
    clock_object: &Clock,
    coin_metadata: &CoinMetadata<T>,
    borrow_cap: u64,
    collateral_cap: u64,
    ltv: u256,
    allocation_points: u256,
    penalty_fee: u256,
    protocol_percentage: u256,
    can_be_collateral: bool,
    ctx: &mut TxContext
    ) {
    // Make sure the protocol can not seize the entire value of a position during liquidations
    assert!(TWENTY_FIVE_PER_CENT >= penalty_fee, ERROR_VALUE_TOO_HIGH);
    assert!(TWENTY_FIVE_PER_CENT >= protocol_percentage, ERROR_VALUE_TOO_HIGH);

    let key = get_type_name_string<T>();

    // We need this to loop through all the markets
    vector::push_back(&mut money_market_storage.all_markets_keys, key);

    let decimals_factor = math::pow(10, coin::get_decimals(coin_metadata));

    // Register the Market
    object_table::add(
      &mut money_market_storage.market_data_table, 
      key,
      Market {
        id: object::new(ctx),
        total_reserves: 0,
        accrued_timestamp: clock::timestamp_ms(clock_object),
        borrow_cap,
        collateral_cap,
        balance_value: 0,
        is_paused: false,
        can_be_collateral,
        ltv,
        reserve_factor: INITIAL_RESERVE_FACTOR_MANTISSA,
        allocation_points,
        accrued_collateral_rewards_per_share: 0,
        accrued_loan_rewards_per_share: 0,
        collateral_rebase: rebase::new(),
        loan_rebase: rebase::new(),
        decimals_factor
    });

    // Register the liquidation data
    table::add(
      &mut money_market_storage.liquidation_table,
      key,
      Liquidation {
        penalty_fee,
        protocol_percentage
      }
    );

    // Add the market tokens
    bag::add(
      &mut money_market_storage.market_balance_bag, 
      key,
      MarketBalance {
        balance: balance::zero<T>()
      });  

    // Add bag to store address -> account
    object_table::add(
      &mut money_market_storage.accounts_table,
      key,
      object_table::new(ctx)
    );  

    // Update the total allocation points
    money_market_storage.total_allocation_points = money_market_storage.total_allocation_points + allocation_points;

    emit(
      CreateMarket<T> {
        borrow_cap,
        collateral_cap,
        ltv,
        reserve_factor: INITIAL_RESERVE_FACTOR_MANTISSA,
        allocation_points,
        decimals_factor
      }
    );
  }

  /**
  * @notice It allows the admin to pause the market
  * @param _ The MoneyMarketAdminCap
  * @param money_market_storage The shared storage object of this module
  */
  entry public fun pause_market<T>(_: &MoneyMarketAdminCap, money_market_storage: &mut MoneyMarketStorage) {
    let market_data = borrow_mut_market_data(&mut money_market_storage.market_data_table, get_type_name_string<T>());
    market_data.is_paused = true;
    emit(Paused<T> {});
  }

  /**
  * @notice It allows the admin to unpause the market
  * @param _ The MoneyMarketAdminCap
  * @param money_market_storage The shared storage object of this module
  */
  entry public fun unpause_market<T>(_: &MoneyMarketAdminCap, money_market_storage: &mut MoneyMarketStorage) {
    let market_data = borrow_mut_market_data(&mut money_market_storage.market_data_table, get_type_name_string<T>());
    market_data.is_paused = false;
    emit(UnPaused<T> {});
  }

  /**
  * @notice It allows the admin to update the borrowing cap for Market T
  * @param _ The MoneyMarketAdminCap
  * @param money_market_storage The shared storage object of this module
  * @param borrow_cap The new borrow cap for Market T
  */
  entry public fun set_borrow_cap<T>(
    _: &MoneyMarketAdminCap, 
     money_market_storage: &mut MoneyMarketStorage,
    borrow_cap: u64
    ) {
    let market_data = borrow_mut_market_data(&mut money_market_storage.market_data_table, get_type_name_string<T>());
     
     market_data.borrow_cap = borrow_cap;

     emit(SetBorrowCap<T> { borrow_cap });
  }

  /**
  * @notice It allows the admin to update the reserve factor for Market T
  * @param _ The MoneyMarketAdminCap
  * @param money_market_storage The shared storage object of this module
  * @param interest_rate_model_storage The shared storage object of money_market::interest_rate_model
  * @param clock_object The shared Clock object
  * @param new_reserve_factor The new reserve factor for the market
  */
  entry public fun update_reserve_factor<T>(
    _: &MoneyMarketAdminCap, 
    money_market_storage: &mut MoneyMarketStorage,
    interest_rate_model_storage: &InterestRateModelStorage,
    clock_object: &Clock,
    new_reserve_factor: u256
    ) {
    assert!(TWENTY_FIVE_PER_CENT >= new_reserve_factor, ERROR_VALUE_TOO_HIGH);
    let market_key = get_type_name_string<T>();
    assert!(market_key != get_type_name_string<SUID>(), ERROR_SUID_OPERATION_NOT_ALLOWED);

    let total_allocation_points = money_market_storage.total_allocation_points;
    let ipx_per_ms = money_market_storage.ipx_per_ms;
    let market_data = borrow_mut_market_data(&mut money_market_storage.market_data_table, market_key);

    // We need to update the loan information before updating the reserve factor
    accrue_internal(
      market_data, 
      interest_rate_model_storage, 
      clock_object,
      market_key, 
      ipx_per_ms,
      total_allocation_points,
    );

    market_data.reserve_factor = new_reserve_factor;

    emit(UpdateReserveFactor<T> { reserve_factor: new_reserve_factor });
  }

  /**
  * @notice It allows the admin to withdraw the reserves for Market T
  * @param _ The MoneyMarketAdminCap
  * @param money_market_storage The shared storage object of this module
  * @param interest_rate_model_storage The shared storage object of money_market::interest_rate_model
  * @param suid_storage The shared object of the module sui_dollar::suid
  * @param clock_object The shared Clock object
  * @param withdraw_value The value of reserves to withdraw
  */
  entry public fun withdraw_reserves<T>(
    _: &MoneyMarketAdminCap, 
    money_market_storage: &mut MoneyMarketStorage,
    interest_rate_model_storage: &InterestRateModelStorage,
    suid_storage: &mut SuiDollarStorage,
    clock_object: &Clock,
    withdraw_value: u64,
    ctx: &mut TxContext
  ) {
    let market_key = get_type_name_string<T>();
    let suid_interest_rate_per_ms = money_market_storage.suid_interest_rate_per_ms;
    let ipx_per_ms = money_market_storage.ipx_per_ms;
    let total_allocation_points = money_market_storage.total_allocation_points;
    let market_data = borrow_mut_market_data(&mut money_market_storage.market_data_table, market_key);

    let is_suid = market_key == get_type_name_string<SUID>();

    if (is_suid) {
      accrue_internal_suid(
        market_data, 
        clock_object,
        suid_interest_rate_per_ms,
        ipx_per_ms,
        total_allocation_points,
       );
    } else {
      // Need to update the loan information before withdrawing the reserves
      accrue_internal(
        market_data, 
        interest_rate_model_storage, 
        clock_object,
        market_key, 
        ipx_per_ms,
        total_allocation_points
      );

      // There must be enough reserves and cash in the market
      assert!(market_data.balance_value >= withdraw_value, ERROR_NOT_ENOUGH_CASH_TO_WITHDRAW);
      // Need to reduce the cash
      market_data.balance_value = market_data.balance_value - withdraw_value;
    };

    assert!(market_data.total_reserves >= withdraw_value, ERROR_NOT_ENOUGH_RESERVES);
    market_data.total_reserves = market_data.total_reserves - withdraw_value;

    if (is_suid) {
       transfer::public_transfer(
        suid::mint(suid_storage, &money_market_storage.publisher, withdraw_value, ctx),
        tx_context::sender(ctx)
      );
    } else {
      // Send tokens to the admin
      transfer::public_transfer(
        coin::take<T>(&mut borrow_mut_market_balance<T>(&mut money_market_storage.market_balance_bag, market_key).balance,  withdraw_value, ctx),
        tx_context::sender(ctx)
      );
    };

    emit(WithdrawReserves<T> { value: withdraw_value });
  }

  /**
  * @notice It allows the admin to update the LTV of a market
  * @param _ The MoneyMarketAdminCap
  * @param money_market_storage The shared storage object of this module
  * @param interest_rate_model_storage The shared storage object of money_market::interest_rate_model
  * @param clock_object The shared Clock object
  * @param new_ltv The new LTV for the market
  */
  entry public fun update_ltv<T>(
    _: &MoneyMarketAdminCap, 
    money_market_storage: &mut MoneyMarketStorage,
    interest_rate_model_storage: &InterestRateModelStorage,
    clock_object: &Clock,
    new_ltv: u256
    ) {
    let market_key = get_type_name_string<T>();
    let suid_interest_rate_per_ms = money_market_storage.suid_interest_rate_per_ms;
    let ipx_per_ms = money_market_storage.ipx_per_ms;
    let total_allocation_points = money_market_storage.total_allocation_points;
    let market_data = borrow_mut_market_data(&mut money_market_storage.market_data_table, market_key);

    if (market_key == get_type_name_string<SUID>()) {
      accrue_internal_suid(
        market_data, 
        clock_object, 
        suid_interest_rate_per_ms,
        ipx_per_ms,
        total_allocation_points
       );
    } else {
      // Need to update the loan information before withdrawing the reserves
      accrue_internal(
        market_data, 
        interest_rate_model_storage, 
        clock_object,
        market_key, 
        ipx_per_ms,
        total_allocation_points
      );
    };

    market_data.ltv = new_ltv;

    emit(UpdateLTV<T> { ltv: new_ltv });
  }

  /**
  * @notice It allows the admin to update the suid interest rate per millisecond
  * @param _ The MoneyMarketAdminCap
  * @param money_market_storage The shared storage object of this module
  * @param clock_object The shared Clock object
  * @param new_interest_rate_per_year The new SuiDollar interest rate
  */
  entry public fun update_suid_interest_rate_per_ms(
    _: &MoneyMarketAdminCap, 
    money_market_storage: &mut MoneyMarketStorage,
    clock_object: &Clock,
    new_interest_rate_per_year: u64
  ) {
    assert!(MAX_SUID_INTEREST_RATE_PER_YEAR > new_interest_rate_per_year, ERROR_INTEREST_RATE_OUT_OF_BOUNDS);
    // Get SUID key
    let market_key = get_type_name_string<SUID>();
    let suid_interest_rate_per_ms = money_market_storage.suid_interest_rate_per_ms;
    let ipx_per_ms = money_market_storage.ipx_per_ms;
    let total_allocation_points = money_market_storage.total_allocation_points;
    let market_data = borrow_mut_market_data(&mut money_market_storage.market_data_table, market_key);

    // Update the SuiDollar market before updating the interest rate
    accrue_internal_suid(
      market_data, 
      clock_object,
      suid_interest_rate_per_ms,
      ipx_per_ms,
      total_allocation_points
    );

    let new_interest_rate = new_interest_rate_per_year / get_ms_per_year();

    emit(
      UpdateSUIDInterestRate {
        old_value: money_market_storage.suid_interest_rate_per_ms,
        new_value: new_interest_rate
      }
    );

    money_market_storage.suid_interest_rate_per_ms = new_interest_rate;
  }

  /**
  * @notice It allows the admin to decide if a market can be used as collateral
  * @param _ The MoneyMarketAdminCap
  * @param money_market_storage The shared storage object of this module
  * @param can_be_collateral It indicates if a market can be used as collateral
  */
  entry public fun update_can_be_collateral<T>(
    _: &MoneyMarketAdminCap, 
    money_market_storage: &mut MoneyMarketStorage,
    can_be_collateral: bool
  ) {
    // Get SUID key
    let market_key = get_type_name_string<T>();
    let market_data = borrow_mut_market_data(&mut money_market_storage.market_data_table, market_key);

    market_data.can_be_collateral = can_be_collateral;

    emit(CanBeCollateral<T> { state: can_be_collateral });
  }

  /**
  * @notice It allows the admin to update the allocation points for Market T
  * @param _ The MoneyMarketAdminCap
  * @param money_market_storage The shared storage object of this module
  * @param interest_rate_model_storage The shared storage object of money_market::interest_rate_model
  * @param clock_object The shared Clock object
  * @param new_allocation_points The new allocation points for Market T
  */
  entry public fun update_allocation_points<T>(
    _: &MoneyMarketAdminCap, 
    money_market_storage: &mut MoneyMarketStorage,
    interest_rate_model_storage: &InterestRateModelStorage,
    clock_object: &Clock,
    new_allocation_points: u256
  ) {
    let market_key = get_type_name_string<T>();
    let suid_interest_rate_per_ms = money_market_storage.suid_interest_rate_per_ms;
    let ipx_per_ms = money_market_storage.ipx_per_ms;
    let total_allocation_points = money_market_storage.total_allocation_points;
    let market_data = borrow_mut_market_data(&mut money_market_storage.market_data_table, market_key);

    if (market_key == get_type_name_string<SUID>()) {
      accrue_internal_suid(
        market_data, 
        clock_object,
        suid_interest_rate_per_ms,
        ipx_per_ms,
        total_allocation_points
       );
    } else {
      // Need to update the loan information before withdrawing the reserves
      accrue_internal(
        market_data, 
        interest_rate_model_storage, 
        clock_object,
        market_key, 
        ipx_per_ms,
        total_allocation_points
      );
    };

    let old_allocation_points = market_data.allocation_points;
    // Update the market allocation points
    market_data.allocation_points = new_allocation_points;
    // Update the total allocation points
    money_market_storage.total_allocation_points = money_market_storage.total_allocation_points + new_allocation_points - old_allocation_points;

    emit(UpdateAllocationPoints<T> { allocation_points: new_allocation_points });
  }

  /**
  * @notice It allows the admin to update the IPX minted per millisecond
  * @param _ The MoneyMarketAdminCap
  * @param money_market_storage The shared storage object of this module
  * @param interest_rate_model_storage The shared storage object of money_market::interest_rate_model
  * @param clock_object The shared Clock object
  * @param new_ipx_per_epoch The value of Coin<IPX> that this module will mint per epoch
  */
  entry public fun update_ipx_per_ms(
    _: &MoneyMarketAdminCap, 
    money_market_storage: &mut MoneyMarketStorage,
    interest_rate_model_storage: &InterestRateModelStorage,
    clock_object: &Clock,
    new_ipx_per_ms: u64
  ) {
    let suid_interest_rate_per_ms = money_market_storage.suid_interest_rate_per_ms;
    let ipx_per_ms = money_market_storage.ipx_per_ms;
    let total_allocation_points = money_market_storage.total_allocation_points;

    let num_of_markets = vector::length(&money_market_storage.all_markets_keys);
    let index = 0;

    // We need to update all market rewards before updating the IPX per millisecond
    while (index < num_of_markets) {
      let key = *vector::borrow(&money_market_storage.all_markets_keys, index);

      if (key == get_type_name_string<SUID>()) {
        accrue_internal_suid(
          borrow_mut_market_data(&mut money_market_storage.market_data_table, key), 
          clock_object,
          suid_interest_rate_per_ms,
          ipx_per_ms,
          total_allocation_points,
        );
    } else {
      // Need to update the loan information before withdrawing the reserves
      accrue_internal(
        borrow_mut_market_data(&mut money_market_storage.market_data_table, key), 
        interest_rate_model_storage, 
        clock_object,
        key,
        ipx_per_ms,
        total_allocation_points
      );
    };

      index = index + 1;
    };

    // Update the IPX per ms
    money_market_storage.ipx_per_ms = new_ipx_per_ms;

    emit(UpdateIPXPerMS { ipx_per_ms: new_ipx_per_ms });
  }

  /**
  * @notice It allows the admin to transfer the rights to a new admin
  * @param whirpool_admin_cap The MoneyMarketAdminCap
  * @param new_admin The address f the new admin
  * Requirements: 
  * - The new_admin cannot be the address zero.
  */
  entry public fun transfer_admin_cap(
    whirpool_admin_cap: MoneyMarketAdminCap, 
    new_admin: address
  ) {
    assert!(new_admin != @0x0, ERROR_NO_ADDRESS_ZERO);
    transfer::transfer(whirpool_admin_cap, new_admin);
    emit(NewAdmin { admin: new_admin });
  }

  // SUID operations


  /**
  * @notice It allows a user to borrow Coin<SUID>.  
  * @param money_market_storage The shared storage object of this module
  * @param interest_rate_model_storage The shared storage object of money_market::interest_rate_model
  * @param ipx_storage The shared object of the module ipx::ipx 
  * @param suid_storage The shared object of the module sui_dollar::suid 
  * @param price_potatoes A vector of price hot potatoes
  * @param clock_object The shared Clock object
  * @param borrow_value The value of Coin<T> the user wishes to borrow
  * @return (Coin<SUID>, Coin<IPX>)
  * Requirements: 
  * - Market is not paused 
  * - User is solvent after borrowing Coin<SUID> collateral
  * - Market borrow cap has not been reached
  */
  public fun borrow_suid(
    money_market_storage: &mut MoneyMarketStorage,
    interest_rate_model_storage: &InterestRateModelStorage,
    ipx_storage: &mut IPXStorage,
    suid_storage: &mut SuiDollarStorage,
    price_potatoes: vector<PricePotato>,
    clock_object: &Clock,
    borrow_value: u64,
    ctx: &mut TxContext
  ): (Coin<SUID>, Coin<IPX>) {
    // Get the type name of the Coin<SUID> of this market.
    let market_key = get_type_name_string<SUID>();
      
    // Get market core information
    let market_data = borrow_mut_market_data(&mut money_market_storage.market_data_table, market_key);

    // Update the market rewards & loans before any mutations
    accrue_internal_suid(
      market_data, 
      clock_object,
      money_market_storage.suid_interest_rate_per_ms,
      money_market_storage.ipx_per_ms,
      money_market_storage.total_allocation_points
    );

    // Save the sender address in memory
    let sender = tx_context::sender(ctx);

    // Init the account if the user never borrowed or deposited in this market
    init_account(&mut money_market_storage.accounts_table, sender, market_key, ctx);

    // Register market in vector if the user never entered any market before
    init_markets_in(&mut money_market_storage.markets_in_table, sender);

    // Get the user account
    let account = borrow_mut_account(&mut money_market_storage.accounts_table, sender, market_key);

    let pending_rewards = 0;
    // If the sender has a loan already, we need to calculate his rewards before this loan.
    if (account.principal > 0) 
      // Math: we need to remove the decimals of shares during fixed point multiplication to maintain IPX decimal houses
      pending_rewards = (
        (account.principal as u256) * 
        market_data.accrued_loan_rewards_per_share / 
        (market_data.decimals_factor as u256)) - 
        account.loan_rewards_paid;

    // Update the loan rebase with the new loan
    let borrow_principal = rebase::add_elastic(&mut market_data.loan_rebase, borrow_value, true);

    // Update the principal owed by the sender
    account.principal = account.principal + borrow_principal; 
    // Consider all rewards paid
    account.loan_rewards_paid = (account.principal as u256) * market_data.accrued_loan_rewards_per_share / (market_data.decimals_factor as u256);

    // Check should be the last action after all mutations
    borrow_allowed(
      money_market_storage, 
      &get_price(price_potatoes), 
      interest_rate_model_storage, 
      clock_object,
      market_key, 
      sender
    );

    emit(
      Borrow<SUID> {
        principal: borrow_principal,
        value: borrow_value,
        pending_rewards,
        sender
      }
    );

    (
      suid::mint(suid_storage, &money_market_storage.publisher, borrow_value, ctx), 
      mint_ipx(money_market_storage, ipx_storage, pending_rewards, ctx)
    )
  }

  /**
  * @notice It allows a user to repay his principal of Coin<SUID>.  
  * @param money_market_storage The shared storage object of this module
  * @param ipx_storage The shared object of the module ipx::ipx 
  * @param suid_storage The shared object of the module sui_dollar::suid 
  * @param clock_object The shared Clock object
  * @param asset The Coin<SUID> he is repaying. 
  * @param principal_to_repay The principle he wishes to repay
  * @return (Coin<SUID> extra , Coin<IPX> rewards)
  * Requirements: 
  * - Market is not paused 
  */
  public fun repay_suid(
    money_market_storage: &mut MoneyMarketStorage, 
    ipx_storage: &mut IPXStorage, 
    suid_storage: &mut SuiDollarStorage,
    clock_object: &Clock,
    asset: Coin<SUID>,
    principal_to_repay: u64,
    ctx: &mut TxContext 
  ): (Coin<SUID>, Coin<IPX>) {
  // Get the type name of the Coin<SUID> of this market.
    let market_key = get_type_name_string<SUID>();
      
    // Get market core information
    let market_data = borrow_mut_market_data(&mut money_market_storage.market_data_table, market_key);

    // Update the market rewards & loans before any mutations
    accrue_internal_suid(
      market_data, 
      clock_object,
      money_market_storage.suid_interest_rate_per_ms,
      money_market_storage.ipx_per_ms,
      money_market_storage.total_allocation_points
    );
    
    // Save the sender in memory
    let sender = tx_context::sender(ctx);

    // Get the sender account
    let account = borrow_mut_account(&mut money_market_storage.accounts_table, sender, market_key);

    // Calculate the sender rewards before repayment
    // Math: we need to remove the decimals of shares during fixed point multiplication to maintain IPX decimal houses
    let pending_rewards = (
        (account.principal as u256) * 
        market_data.accrued_loan_rewards_per_share / 
        (market_data.decimals_factor as u256)) - 
        account.loan_rewards_paid;

    // Save the value of Coin<T> in memory
    let asset_value = coin::value(&asset);

    // Convert asset_value to principal
    let asset_principal = rebase::to_base(&market_data.loan_rebase, asset_value, false);

    // Ensure that the user is not overpaying his loan. This is important because interest rate keeps accrueing every second.
    // Users will usually send more Coin<T> than needed
    let safe_asset_principal = if (asset_principal > account.principal) { math::min(principal_to_repay, account.principal )} else { math::min(asset_principal, principal_to_repay) };

    // Convert the safe principal to Coin<T> value so we can send any extra back to the user
    let repay_amount = rebase::to_elastic(&market_data.loan_rebase, safe_asset_principal, true);

    // If the sender send more Coin<SUID> then necessary, we return the extra to him
    let extra_coin = if (asset_value > repay_amount) { coin::split(&mut asset, asset_value - repay_amount, ctx) } else { coin::zero<SUID>(ctx) };
    // Reduce the total principal
    rebase::sub_base(&mut market_data.loan_rebase, safe_asset_principal, true);

    // Remove the principal repaid from the user account
    account.principal = account.principal - safe_asset_principal;
    // Consider all rewards paid
    account.loan_rewards_paid = (account.principal as u256) * market_data.accrued_loan_rewards_per_share / (market_data.decimals_factor as u256);

    // Burn the SUID
    suid::burn(suid_storage, asset);

    repay_allowed(market_data);

    emit(
      Repay<SUID> {
        principal: safe_asset_principal,
        value: repay_amount,
        pending_rewards,
        sender
      }
    );

    (extra_coin, mint_ipx(money_market_storage, ipx_storage, pending_rewards, ctx))
  }

  /**
  * @notice It allows the sender to get his collateral and loan Coin<IPX> rewards for Market T
  * @param money_market_storage The shared storage object of this module
  * @param interest_rate_model_storage The shared storage object of money_market::interest_rate_model
  * @param ipx_storage The shared object of the module ipx::ipx 
  * @param clock_object The shared Clock object
  * @return Coin<IPX> It will mint IPX rewards to the user.
  */
  public fun get_rewards<T>(
    money_market_storage: &mut MoneyMarketStorage, 
    interest_rate_model_storage: &InterestRateModelStorage,
    ipx_storage: &mut IPXStorage, 
    clock_object: &Clock,
    ctx: &mut TxContext 
  ): Coin<IPX> {

    let sender = tx_context::sender(ctx);

    // Call the view functions to get the values
    let (collateral_rewards, loan_rewards) = get_pending_rewards<T>(
      money_market_storage, 
      interest_rate_model_storage, 
      clock_object,
      sender
     ); 

    let rewards = collateral_rewards + loan_rewards;

    emit(
      GetRewards<T> {
        rewards,
        sender
      }
    );

    // Mint the IPX
    mint_ipx(money_market_storage, ipx_storage, rewards, ctx)
  }

  /**
  * @notice It allows the sender to get his collateral and loan Coin<IPX> rewards for ALL markets
  * @param money_market_storage The shared storage object of this module
  * @param interest_rate_model_storage The shared storage object of money_market::interest_rate_model
  * @param ipx_storage The shared object of the module ipx::ipx 
  * @param clock_object The shared Clock object
  * @return Coin<IPX> It will mint IPX rewards to the user.
  */
  public fun get_all_rewards(
    money_market_storage: &mut MoneyMarketStorage, 
    interest_rate_model_storage: &InterestRateModelStorage,
    ipx_storage: &mut IPXStorage, 
    clock_object: &Clock,
    ctx: &mut TxContext 
  ): Coin<IPX> {
    let all_market_keys = money_market_storage.all_markets_keys;

    // We need to know how many markets exist to loop through them
    let num_of_markets = vector::length(&all_market_keys);

    let index = 0;
    let all_rewards = 0;
    let sender = tx_context::sender(ctx);

    while(index < num_of_markets) {
      let key = *vector::borrow(&all_market_keys, index);

      let (collateral_rewards, loan_rewards) = get_pending_rewards_internal(
        money_market_storage,
        interest_rate_model_storage, 
        clock_object,
        key,
        sender
      );  

      // Add the rewards
      all_rewards = all_rewards + collateral_rewards + loan_rewards;
      // Inc index
      index = index + 1;
    };

    emit(
      GetAllRewards {
        rewards: all_rewards,
        sender
      }
    );

    // mint Coin<IPX>
    mint_ipx(money_market_storage, ipx_storage, all_rewards, ctx)
  }


   /**
  * @notice It allows the caller to get the value of a user collateral and loan rewards
  * @param money_market_storage The shared storage object of this module
  * @param interest_rate_model_storage The shared storage object of money_market::interest_rate_model
  * @param ipx_storage The shared object of the module ipx::ipx 
  * @param clock_object The shared Clock object
  * @param user The address of the account
  * @return Coin<IPX> It will mint IPX rewards to the user.
  */
  public fun get_pending_rewards<T>(
    money_market_storage: &mut MoneyMarketStorage, 
    interest_rate_model_storage: &InterestRateModelStorage,
    clock_object: &Clock,
    user: address
  ): (u256, u256) {
    // Get the type name of the Coin<T> of this market.
    let market_key = get_type_name_string<T>();

    get_pending_rewards_internal(
      money_market_storage,
      interest_rate_model_storage, 
      clock_object,
      market_key,
      user
    )  
  }

 /**
  * @notice It allows a user to liquidate a borrower for a reward 
  * @param money_market_storage The shared storage object of this module
  * @param interest_rate_model_storage The shared storage object of money_market::interest_rate_model
  * @param ipx_storage The shared object of the module ipx::ipx 
  * @param price_potatoes A Vector of price potatoes from the Oracle
  * @param asset The Coin<L> he is repaying. 
  * @param principal_to_repay The principal amount he wishes to repay
  * Requirements: 
  * - borrower is insolvent
  */
  public fun liquidate<C, L>(
    money_market_storage: &mut MoneyMarketStorage,
    interest_rate_model_storage: &InterestRateModelStorage,
    ipx_storage: &mut IPXStorage,
    price_potatoes: vector<PricePotato>,
    clock_object: &Clock,
    asset: Coin<L>,
    borrower: address,
    ctx: &mut TxContext
  ): Coin<L> {
    // Get keys for collateral, loan and SUID market
    let collateral_market_key = get_type_name_string<C>();
    let loan_market_key = get_type_name_string<L>();
    let suid_market_key = get_type_name_string<SUID>();
    let liquidator_address = tx_context::sender(ctx);
    
    let ipx_per_ms = money_market_storage.ipx_per_ms;
    let total_allocation_points = money_market_storage.total_allocation_points;

   // Get liquidation info for the collateral market
    let liquidation = table::borrow(&money_market_storage.liquidation_table, collateral_market_key);

    let penalty_fee = liquidation.penalty_fee;
    let protocol_fee = liquidation.protocol_percentage;

    // User cannot liquidate himself
    assert!(liquidator_address != borrower, ERROR_LIQUIDATOR_IS_BORROWER);
    // SUID cannot be used as collateral
    // SUID liquidation has its own function
    assert!(collateral_market_key != suid_market_key, ERROR_SUID_OPERATION_NOT_ALLOWED);
    assert!(loan_market_key != suid_market_key, ERROR_SUID_OPERATION_NOT_ALLOWED);

    // Update the collateral market
    accrue_internal(
      borrow_mut_market_data(&mut money_market_storage.market_data_table, collateral_market_key), 
      interest_rate_model_storage,
      clock_object, 
      collateral_market_key, 
      ipx_per_ms,
      total_allocation_points
    );
    // Update the loan market
    accrue_internal(
      borrow_mut_market_data(&mut money_market_storage.market_data_table, loan_market_key), 
      interest_rate_model_storage,
      clock_object, 
      loan_market_key, 
      ipx_per_ms,
      total_allocation_points
    );

    // Accounts must exist or there is no point o proceed.
    assert!(account_exists(&money_market_storage.accounts_table, borrower, collateral_market_key), ERROR_ACCOUNT_COLLATERAL_DOES_EXIST);
    assert!(account_exists(&money_market_storage.accounts_table, borrower, loan_market_key), ERROR_ACCOUNT_LOAN_DOES_EXIST);

    // If the liquidator does not have an account in the collateral market, we make one. 
    // So he can accept the collateral
    init_account(&mut money_market_storage.accounts_table, liquidator_address, collateral_market_key, ctx);

    let price_map = get_price(price_potatoes);
    
    // User must be insolvent
    assert!(!is_user_solvent(
      money_market_storage, 
      &price_map, 
      interest_rate_model_storage, 
      clock_object,
      borrower
     ), 
     ERROR_USER_IS_SOLVENT);

    // Get the borrower's loan account information
    let borrower_loan_account = borrow_mut_account(&mut money_market_storage.accounts_table, borrower, loan_market_key);
    // Convert the principal to a nominal amount
    let borrower_loan_amount = rebase::to_elastic(
      &borrow_market_data(&money_market_storage.market_data_table, loan_market_key).loan_rebase, 
      borrower_loan_account.principal, 
      true
      );

    // Get the value the liquidator wishes to repay
    let asset_value = coin::value(&asset);

    // The liquidator cannot liquidate more than the total loan
    let repay_max_amount = if (asset_value > borrower_loan_amount) { borrower_loan_amount } else { asset_value };

    // Liquidator must liquidate a value greater than 0, or no point to proceed
    assert!(repay_max_amount != 0, ERROR_ZERO_LIQUIDATION_AMOUNT);

    // Calculate the amount of asset to return to the caller
    let extra_coin = if (asset_value > repay_max_amount) { coin::split(&mut asset, asset_value - repay_max_amount, ctx) } else { coin::zero<L>(ctx) };

    // Deposit the coins in the market
    balance::join(&mut borrow_mut_market_balance<L>(&mut money_market_storage.market_balance_bag, loan_market_key).balance, coin::into_balance(asset));
    let loan_market_data = borrow_mut_market_data(&mut money_market_storage.market_data_table, loan_market_key);
    
    // Update the cash in the loan market
    loan_market_data.balance_value = loan_market_data.balance_value + repay_max_amount;

    // Convert the repay amount to principal
    let base_repay = rebase::to_base(&loan_market_data.loan_rebase, repay_max_amount, true);

    // We need to send the user his loan rewards before the liquidation
    let pending_rewards =  (
        (borrower_loan_account.principal as u256) * 
        loan_market_data.accrued_loan_rewards_per_share / 
        (loan_market_data.decimals_factor as u256)) - 
        borrower_loan_account.loan_rewards_paid;

    let principal_repaid = math::min(base_repay, borrower_loan_account.principal);    
    
    // Consider the loan repaid
    // Update the user principal info
    borrower_loan_account.principal = borrower_loan_account.principal - principal_repaid;

    // Consider his loan rewards paid.
    borrower_loan_account.loan_rewards_paid = (borrower_loan_account.principal as u256) * loan_market_data.accrued_loan_rewards_per_share / (loan_market_data.decimals_factor as u256);

    let loan_decimals_factor = loan_market_data.decimals_factor;

    // Update the market loan info
    rebase::sub_base(&mut loan_market_data.loan_rebase, base_repay, false);

    let collateral_price_normalized = vec_map::get(&price_map, &collateral_market_key).value;
    let loan_price_normalized = vec_map::get(&price_map, &loan_market_key).value;

    let collateral_market_data = borrow_market_data(&mut money_market_storage.market_data_table, collateral_market_key);

    let collateral_seize_amount = (d_fdiv_u256(d_fmul_u256(loan_price_normalized, (repay_max_amount as u256)), (collateral_price_normalized as u256)) * (collateral_market_data.decimals_factor as u256)) / (loan_decimals_factor as u256); 

    let penalty_fee_amount = d_fmul_u256(collateral_seize_amount, penalty_fee);
    let collateral_seize_amount_with_fee = collateral_seize_amount + penalty_fee_amount;

    // Calculate how much collateral to assign to the protocol and liquidator
    let protocol_amount = d_fmul_u256(penalty_fee_amount, protocol_fee);
    let liquidator_amount = collateral_seize_amount_with_fee - protocol_amount;

    // Get the borrower collateral account
    let borrower_collateral_account = borrow_mut_account(&mut money_market_storage.accounts_table, borrower, collateral_market_key);

    // We need to add the collateral rewards to the user.
    // Math: we need to remove the decimals of shares during fixed point multiplication to maintain IPX decimal houses
    pending_rewards = pending_rewards + ((borrower_collateral_account.shares as u256) * 
          collateral_market_data.accrued_collateral_rewards_per_share / 
          (collateral_market_data.decimals_factor as u256)) - 
          borrower_collateral_account.collateral_rewards_paid;

    // Remove the shares from the borrower
    borrower_collateral_account.shares = borrower_collateral_account.shares - math::min(rebase::to_base(&collateral_market_data.collateral_rebase, (collateral_seize_amount_with_fee as u64), true), borrower_collateral_account.shares);

    // Consider all rewards earned by the sender paid
    borrower_collateral_account.collateral_rewards_paid = (borrower_collateral_account.shares as u256) * collateral_market_data.accrued_collateral_rewards_per_share / (collateral_market_data.decimals_factor as u256);

    // Give the shares to the liquidator
    let liquidator_collateral_account = borrow_mut_account(&mut money_market_storage.accounts_table, liquidator_address, collateral_market_key);

    liquidator_collateral_account.shares = liquidator_collateral_account.shares + rebase::to_base(&collateral_market_data.collateral_rebase, (liquidator_amount as u64), false);
    
    // Consider the liquidator rewards paid
    liquidator_collateral_account.collateral_rewards_paid = (liquidator_collateral_account.shares as u256) * collateral_market_data.accrued_collateral_rewards_per_share / (collateral_market_data.decimals_factor as u256);

    // Give reserves to the protocol
    let collateral_market_data = borrow_mut_market_data(&mut money_market_storage.market_data_table, collateral_market_key);
    collateral_market_data.total_reserves = collateral_market_data.total_reserves + (protocol_amount as u64);

    // Send the rewards to the borrower
    transfer::public_transfer(mint_ipx(money_market_storage, ipx_storage, pending_rewards, ctx), borrower);

    emit(Liquidate<C, L> {
        principal_repaid,
        liquidator_amount,
        protocol_amount,
        collateral_seized: collateral_seize_amount_with_fee,
        borrower,
        liquidator: liquidator_address
    });

    extra_coin
  }

  /**
  * @notice It allows a user to liquidate a borrower for a reward 
  * @param money_market_storage The shared storage object of this module
  * @param interest_rate_model_storage The shared storage object of money_market::interest_rate_model
  * @param ipx_storage The shared object of the module ipx::ipx 
  * @param suid_storage The shared object of the module sui_dollar::suid 
  * @param prices A Vector of Hot potatoes
  * @param asset The Coin<SUID> he is repaying. 
  * @param principal_to_repay The principal amount he wishes to repay
  * Requirements: 
  * - borrower is insolvent
  */
  public fun liquidate_suid<C>(
    money_market_storage: &mut MoneyMarketStorage,
    interest_rate_model_storage: &InterestRateModelStorage,
    ipx_storage: &mut IPXStorage,
    suid_storage: &mut SuiDollarStorage,
    price_potatoes: vector<PricePotato>,
    clock_object: &Clock,
    asset: Coin<SUID>,
    borrower: address,
    ctx: &mut TxContext
  ): Coin<SUID> {
    // Get keys for collateral, loan and SUID market
    let collateral_market_key = get_type_name_string<C>();
    let suid_market_key = get_type_name_string<SUID>();
    let liquidator_address = tx_context::sender(ctx);
    
    let suid_interest_rate_per_ms = money_market_storage.suid_interest_rate_per_ms;
    let ipx_per_ms = money_market_storage.ipx_per_ms;
    let total_allocation_points = money_market_storage.total_allocation_points;

    // Get liquidation info for the collateral market
    let liquidation = table::borrow(&money_market_storage.liquidation_table, collateral_market_key);

    let penalty_fee = liquidation.penalty_fee;
    let protocol_fee = liquidation.protocol_percentage;

    // User cannot liquidate himself
    assert!(liquidator_address != borrower, ERROR_LIQUIDATOR_IS_BORROWER);
    // SUID cannot be used as collateral
    assert!(collateral_market_key != suid_market_key, ERROR_SUID_OPERATION_NOT_ALLOWED);

    // Update the collateral market
    accrue_internal(
      borrow_mut_market_data(&mut money_market_storage.market_data_table, collateral_market_key), 
      interest_rate_model_storage,
      clock_object, 
      collateral_market_key, 
      ipx_per_ms,
      total_allocation_points
    );

    // Update the market rewards & loans before any mutations
    accrue_internal_suid(
      borrow_mut_market_data(&mut money_market_storage.market_data_table, suid_market_key), 
      clock_object, 
      suid_interest_rate_per_ms,
      ipx_per_ms,
      total_allocation_points
    );

    // Accounts must exist or there is no point o proceed.
    assert!(account_exists(&money_market_storage.accounts_table, borrower, collateral_market_key), ERROR_ACCOUNT_COLLATERAL_DOES_EXIST);
    assert!(account_exists(&money_market_storage.accounts_table, borrower, suid_market_key), ERROR_ACCOUNT_LOAN_DOES_EXIST);

    // If the liquidator does not have an account in the collateral market, we make one. 
    // So he can accept the collateral
    init_account(&mut money_market_storage.accounts_table, liquidator_address, collateral_market_key, ctx);

    let price_map = get_price(price_potatoes);
    
    // User must be insolvent
    assert!(!is_user_solvent(
      money_market_storage, 
      &price_map, 
      interest_rate_model_storage, 
      clock_object,
      borrower
    ), 
    ERROR_USER_IS_SOLVENT);

    // Get the borrower loan account information
    let borrower_loan_account = borrow_mut_account(&mut money_market_storage.accounts_table, borrower, suid_market_key);

    // Convert the principal to a nominal amount
    let borrower_loan_amount = rebase::to_elastic(
      &borrow_market_data(&money_market_storage.market_data_table, suid_market_key).loan_rebase, 
      borrower_loan_account.principal, 
      true
      );

    // Get the value the liquidator wishes to repay
    let asset_value = coin::value(&asset);

    // The liquidator cannot liquidate more than the total loan
    let repay_max_amount = if (asset_value > borrower_loan_amount) { borrower_loan_amount } else { asset_value };

    // Liquidator must liquidate a value greater than 0, or no point to proceed
    assert!(repay_max_amount != 0, ERROR_ZERO_LIQUIDATION_AMOUNT);

    // Calculate the amount of asset to return to the caller
    let extra_coin = if (asset_value > repay_max_amount) { coin::split(&mut asset, asset_value - repay_max_amount, ctx) } else { coin::zero<SUID>(ctx) };

    // Burn the SUID
    suid::burn(suid_storage, asset);


    let loan_market_data = borrow_mut_market_data(&mut money_market_storage.market_data_table, suid_market_key);

    // Convert the repay amount to principal
    let base_repay = rebase::to_base(&loan_market_data.loan_rebase, repay_max_amount, true);

    // We need to send the user his loan rewards before the liquidation
    let pending_rewards = (
        (borrower_loan_account.principal as u256) * 
        loan_market_data.accrued_loan_rewards_per_share / 
        (loan_market_data.decimals_factor as u256)) - 
        borrower_loan_account.loan_rewards_paid;

    let principal_repaid = math::min(base_repay, borrower_loan_account.principal);     
    
    // Consider the loan repaid
    // Update the user's principal info
    borrower_loan_account.principal = borrower_loan_account.principal - math::min(base_repay, borrower_loan_account.principal);

    // Consider his loan rewards paid.
    borrower_loan_account.loan_rewards_paid = (borrower_loan_account.principal as u256) * loan_market_data.accrued_loan_rewards_per_share / (loan_market_data.decimals_factor as u256);

    // Update the market loan info
    rebase::sub_base(&mut loan_market_data.loan_rebase, base_repay, false);

    let collateral_price_normalized = vec_map::get(&price_map, &collateral_market_key).value;

    let collateral_seize_amount = d_fdiv_u256((repay_max_amount as u256), collateral_price_normalized); 
    let penalty_fee_amount = d_fmul_u256(collateral_seize_amount, penalty_fee);
    let collateral_seize_amount_with_fee = collateral_seize_amount + penalty_fee_amount;

    // Calculate how much collateral to assign to the protocol and liquidator
    let protocol_amount = d_fmul_u256(penalty_fee_amount, protocol_fee);
    let liquidator_amount = collateral_seize_amount_with_fee - protocol_amount;

    // Get the borrower collateral account
    let collateral_market_data = borrow_market_data(&mut money_market_storage.market_data_table, collateral_market_key);
    let borrower_collateral_account = borrow_mut_account(&mut money_market_storage.accounts_table, borrower, collateral_market_key);

    // We need to add the collateral rewards to the user.
    // Math: we need to remove the decimals of shares during fixed point multiplication to maintain IPX decimal houses
    pending_rewards = pending_rewards + ((borrower_collateral_account.shares as u256) * 
          collateral_market_data.accrued_collateral_rewards_per_share / 
          (collateral_market_data.decimals_factor as u256)) - 
          borrower_collateral_account.collateral_rewards_paid;

    // Remove the shares from the borrower
    borrower_collateral_account.shares = borrower_collateral_account.shares - math::min(rebase::to_base(&collateral_market_data.collateral_rebase, (collateral_seize_amount_with_fee as u64), true), borrower_collateral_account.shares);

    // Consider all rewards earned by the sender paid
    borrower_collateral_account.collateral_rewards_paid = (borrower_collateral_account.shares as u256) * collateral_market_data.accrued_collateral_rewards_per_share / (collateral_market_data.decimals_factor as u256);

    // Give the shares to the liquidator
    let liquidator_collateral_account = borrow_mut_account(&mut money_market_storage.accounts_table, liquidator_address, collateral_market_key);

    liquidator_collateral_account.shares = liquidator_collateral_account.shares + rebase::to_base(&collateral_market_data.collateral_rebase, (liquidator_amount as u64), false);

    // Consider the liquidator rewards paid
    liquidator_collateral_account.collateral_rewards_paid = (liquidator_collateral_account.shares as u256) * collateral_market_data.accrued_collateral_rewards_per_share / (collateral_market_data.decimals_factor as u256);

    // Give reserves to the protocol
    let collateral_market_data = borrow_mut_market_data(&mut money_market_storage.market_data_table, collateral_market_key);
    collateral_market_data.total_reserves = collateral_market_data.total_reserves + (protocol_amount as u64);

    // Send the rewards to the borrower
    transfer::public_transfer(mint_ipx(money_market_storage, ipx_storage, pending_rewards, ctx), borrower);

    emit(Liquidate<C, SUID> {
        principal_repaid,
        liquidator_amount,
        protocol_amount,
        collateral_seized: collateral_seize_amount_with_fee,
        borrower,
        liquidator: liquidator_address
    });

    extra_coin
  }

  /**
  * @notice It unpacks the data on a struct Account for a Market T
  * @param money_market_storage The shared MoneyMarketStorage object
  * @param user The address of the account we want to check
  * @return (u64, u64, u256, u256) (shares, principal, collateteral_rewards_paid, loan_rewards_paid)
  */
  public fun get_account_info<T>(money_market_storage: &MoneyMarketStorage, user: address): (u64, u64, u256, u256) {
    let account = borrow_account(&money_market_storage.accounts_table, user, get_type_name_string<T>());
    (account.shares, account.principal, account.collateral_rewards_paid, account.loan_rewards_paid)
  }

  /**
  * @notice It unpacks a Market struct
  * @param money_market_storage The shared MoneyMarketStorage object
  * @return (u64, u64, u64, u64, u64, bool, u256, u256, u256, u256, u256, u64, u64, u64, u64) (total_reserves, accrued_epoch, borrow_cap, collateral_cap, balance_value, is_paused, LTV, reserve_factor, allocation_points, accrued_collateral_rewards_per_share, accrued_loan_rewards_per_share, total_shares, total_collateral, total_principal, total_borrows)
  */
  public fun get_market_info<T>(money_market_storage: &MoneyMarketStorage): (
    u64,
    u64,
    u64,
    u64,
    u64,
    bool,
    u256,
    u256,
    u256,
    u256,
    u256,
    u64,
    u64,
    u64,
    u64,
    bool
  ) {
    let market_data = borrow_market_data(&money_market_storage.market_data_table, get_type_name_string<T>());
    (
      market_data.total_reserves,
      market_data.accrued_timestamp,
      market_data.borrow_cap,
      market_data.collateral_cap,
      market_data.balance_value,
      market_data.is_paused,
      market_data.ltv,
      market_data.reserve_factor,
      market_data.allocation_points,
      market_data.accrued_collateral_rewards_per_share,
      market_data.accrued_loan_rewards_per_share,
      rebase::base(&market_data.collateral_rebase),
      rebase::elastic(&market_data.collateral_rebase),
      rebase::base(&market_data.loan_rebase),
      rebase::elastic(&market_data.loan_rebase),
      market_data.can_be_collateral
    )
  }

  /**
  * @notice It returns a vector with the key of every market the user has an open loan or entered with collateral to back a loan
  * @param interest_rate_model_storage The shared storage object of money_market::interest_rate_model
  * @param user The address of the account we want to check
  * @return &vector<string> A vector of the markets in
  */
  public fun get_user_markets_in(money_market_storage: &MoneyMarketStorage, user: address): &vector<String> {
    borrow_user_markets_in(&money_market_storage.markets_in_table, user)
  }

  // Controller

  /**
  * @notice Defensive hook to make sure the market is not paused and the collateral cap has not been reached
  * @param market_data A Market
  */
  fun deposit_allowed(market_data: &Market) {
    assert!(!market_data.is_paused, ERROR_MARKET_IS_PAUSED);
    assert!(market_data.collateral_cap >= rebase::elastic(&market_data.collateral_rebase), ERROR_MAX_COLLATERAL_REACHED);
  }

   /**
  * @notice Defensive hook to make sure that the user can withdraw
  * @param money_market_storage The shared MoneyMarketStorage object
  * @param price_map A VecMap containing the prices of the coins
  * @param interest_rate_model_storage The shared storage object of money_market::interest_rate_model
  * @param clock_object The shared Clock object
  * @param market_key The key of the market the user is trying to withdraw
  * @param user The address of the user that is trying to withdraw
  * Requirements
  * - The user must be solvent after withdrawing.
  */
  fun withdraw_allowed(
    money_market_storage: &mut MoneyMarketStorage, 
    price_map: &VecMap<String, CoinPrice>,
    interest_rate_model_storage: &InterestRateModelStorage,
    clock_object: &Clock,
    market_key: String,
    user: address
    ) {
    // Market is not paused
    assert!(!borrow_market_data(&money_market_storage.market_data_table, market_key).is_paused, ERROR_MARKET_IS_PAUSED);

    // If the user has no loans, he can withdraw
    if (table::contains(&money_market_storage.markets_in_table, user))
      // Check if the user is solvent
      assert!(is_user_solvent(
        money_market_storage, 
        price_map, 
        interest_rate_model_storage, 
        clock_object,
        user
       ), 
       ERROR_USER_IS_INSOLVENT);
    
  }

  /**
  * @notice Defensive hook to make sure that the user can borrow
  * @param money_market_storage The shared MoneyMarketStorage object
  * @param price_map A VecMap containing the prices of the coins
  * @param interest_rate_model_storage The shared storage object of money_market::interest_rate_model
  * @param clock_object The shared Clock object
  * @param market_key The key of the market the user is trying to borrow from
  * @param user The address of the user that is trying to borrow
  * Requirements
  * - The user must be solvent after withdrawing.
  */
  fun borrow_allowed(
    money_market_storage: &mut MoneyMarketStorage, 
    price_map: &VecMap<String, CoinPrice>,
    interest_rate_model_storage: &InterestRateModelStorage,
    clock_object: &Clock,
    market_key: String,
    user: address
  ) {
      let current_market_data = borrow_market_data(&money_market_storage.market_data_table, market_key);

      assert!(!current_market_data.is_paused, ERROR_MARKET_IS_PAUSED);

      let user_markets_in = borrow_mut_user_markets_in(&mut money_market_storage.markets_in_table, user);

      // We need to add this market to the markets_in if he is getting a loan and is not registered
      if (!vector::contains(user_markets_in, &market_key)) { 
        vector::push_back(user_markets_in, market_key);
      };


      // Ensure that the borrow cap is not met
      assert!(current_market_data.borrow_cap >= rebase::elastic(&current_market_data.loan_rebase), ERROR_BORROW_CAP_LIMIT_REACHED);

      // User must remain solvent
      assert!(is_user_solvent(
        money_market_storage, 
        price_map, 
        interest_rate_model_storage, 
        clock_object,
        user
       ), 
       ERROR_USER_IS_SOLVENT);
  }


  /**
  * @notice Defensive hook to make sure that the user can repay
  * @param market_table The table that holds the Market structs
  */
  fun repay_allowed(market_data: &Market) {
    // Ensure that the market is not paused
    assert!(!market_data.is_paused, ERROR_MARKET_IS_PAUSED);
  }

  /**
  * @notice It allows the caller to get the value of a user collateral and loan rewards
  * @param money_market_storage The shared MoneyMarketStorage object
  * @param interest_rate_model_storage The shared storage object of money_market::interest_rate_model
  * @param clock_object The shared Clock object
  * @param market_key The key of the market
  * @param user The address of the account
  * @return Coin<IPX> It will mint IPX rewards to the user.
  */
  fun get_pending_rewards_internal(
    money_market_storage: &mut MoneyMarketStorage, 
    interest_rate_model_storage: &InterestRateModelStorage,
    clock_object: &Clock,
    market_key: String,
    user: address
  ): (u256, u256) {

    // Reward information in memory
    let suid_interest_rate_per_ms = money_market_storage.suid_interest_rate_per_ms;
    let ipx_per_ms = money_market_storage.ipx_per_ms;
    let total_allocation_points = money_market_storage.total_allocation_points;
      
    // Get market core information
    let market_data = borrow_mut_market_data(&mut money_market_storage.market_data_table, market_key);

    if (market_key == get_type_name_string<SUID>()) {
      accrue_internal_suid(
        market_data, 
        clock_object,
        suid_interest_rate_per_ms,
        ipx_per_ms,
        total_allocation_points,
      );
    } else {
      // Update the market rewards & loans before any mutations
      accrue_internal(
        market_data, 
        interest_rate_model_storage, 
        clock_object,
        market_key, 
        ipx_per_ms,
        total_allocation_points,
        );
    };

      // Get the caller Account to update
      let account = borrow_mut_account(&mut money_market_storage.accounts_table, user, market_key);

      let pending_collateral_rewards = 0;
      let pending_loan_rewards = 0;

      // If the sender has shares already, we need to calculate his rewards before this deposit.
      if (account.shares != 0) 
        // Math: we need to remove the decimals of shares during fixed point multiplication to maintain IPX decimal houses
        pending_collateral_rewards = (
          (account.shares as u256) * 
          market_data.accrued_collateral_rewards_per_share / 
          (market_data.decimals_factor as u256)) - 
          account.collateral_rewards_paid;

       // If the user has a loan in this market, he is entitled to rewards
       if(account.principal != 0) 
        pending_loan_rewards = (
          (account.principal as u256) * 
          market_data.accrued_loan_rewards_per_share / 
          (market_data.decimals_factor as u256)) - 
          account.loan_rewards_paid;

      (pending_collateral_rewards, pending_loan_rewards)      
  }

  /**
  * @notice It checks if a user can meet his obligations after withdrawing and borrowing
  * @param money_market_storage The shared MoneyMarketStorage object
  * @param price_map A VecMap with the prices
  * @param interest_rate_model_storage The shared storage object of money_market::interest_rate_model
  * @param clock_object The shared clock object
  * @param user The address of the user that is trying to borrow or withdraw
  * @return bool true if the user can borrow
  */
  fun is_user_solvent(
    money_market_storage: &mut MoneyMarketStorage,
    price_map: &VecMap<String, CoinPrice>,
    interest_rate_model_storage: &InterestRateModelStorage,
    clock_object: &Clock,
    user: address
    ): bool {
    let suid_interest_rate_per_ms = money_market_storage.suid_interest_rate_per_ms;  
    let ipx_per_ms = money_market_storage.ipx_per_ms;
    let total_allocation_points = money_market_storage.total_allocation_points;

    // Get the list of the markets the user is in. 
    // No point to calculate the data for markets the user is not in.
    let user_markets_in = borrow_mut_user_markets_in(&mut money_market_storage.markets_in_table, user);

    let index = 0;
    let length = vector::length(user_markets_in);

    // Will store the total value in usd for collateral and borrows.
    let total_collateral_in_usd = 0;
    let total_borrows_in_usd = 0;
    
    while(index < length) {
      // Get the key
      let key = *vector::borrow(user_markets_in, index);

      // Get the user account
      let account = object_table::borrow(object_table::borrow(&money_market_storage.accounts_table, key), user);

      // Get the market data
      let market_data = borrow_mut_market_data(&mut money_market_storage.market_data_table, key);
      
      // Get the nominal up to date collateral and borrow balance
      let (collateral_balance, borrow_balance) = get_account_balances_internal(
        market_data,
        account, 
        interest_rate_model_storage, 
        clock_object,
        key, 
        suid_interest_rate_per_ms,
        ipx_per_ms,
        total_allocation_points
      );

      // Get the price of the Coin
      let price_normalized = vec_map::get(price_map, &key).value;

      // Make sure the price is not zero
      assert!(price_normalized != 0, ERROR_ZERO_ORACLE_PRICE);

      // Update the collateral and borrow
      total_collateral_in_usd = total_collateral_in_usd + d_fmul_u256(d_fmul_u256((collateral_balance as u256) * double_scalar() / (market_data.decimals_factor as u256), price_normalized), (market_data.ltv as u256));

      total_borrows_in_usd = total_borrows_in_usd + d_fmul_u256((borrow_balance as u256) * double_scalar() / (market_data.decimals_factor as u256), price_normalized);

      // increment the index 
      index = index + 1;
    };

    // Make sure the user is solvent
    total_collateral_in_usd > total_borrows_in_usd
  }

  // Test functions 

  #[test_only]
  public fun get_interest_rate_per_ms(storage: &MoneyMarketStorage): u64 {
    storage.suid_interest_rate_per_ms
  }

  #[test_only]
  public fun get_publisher_id(storage: &MoneyMarketStorage): ID {
    object::id(&storage.publisher)
  }

  #[test_only]
  public fun init_for_testing(ctx: &mut TxContext) {
    init(IPX_MONEY_MARKET {}, ctx);
  }

  #[test_only]
  public fun get_liquidation_info<T>(money_market_storage: &MoneyMarketStorage): (u256, u256) {
    let liquidation = table::borrow(&money_market_storage.liquidation_table, get_type_name_string<T>());
    (liquidation.penalty_fee, liquidation.protocol_percentage)
  }

  #[test_only]
  public fun is_market_paused<T>(money_market_storage: &MoneyMarketStorage): bool {
    let market_data = object_table::borrow(&money_market_storage.market_data_table, get_type_name_string<T>());
    market_data.is_paused
  }

  #[test_only]
  public fun get_total_allocation_points(money_market_storage: &MoneyMarketStorage): u256 {
    money_market_storage.total_allocation_points
  }

  #[test_only]
  public fun get_ipx_per_ms(money_market_storage: &MoneyMarketStorage): u64 {
    money_market_storage.ipx_per_ms
  }

  #[test_only]
  public fun get_total_num_of_markets(money_market_storage: &MoneyMarketStorage): u64 {
    vector::length(&money_market_storage.all_markets_keys)
  }
}