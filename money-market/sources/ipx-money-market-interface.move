module money_market::ipx_money_market_interface {

  use std::ascii::{String};
  use std::vector;

  use sui::coin::{Coin};
  use sui::clock::{Clock};
  use sui::sui::{SUI};
  use sui::tx_context::{Self, TxContext};

  use ipx::ipx::{IPXStorage};

  use sui_dollar::suid::{SUID, SuiDollarStorage};

  use oracle::ipx_oracle::{Self, Price as PricePotato, OracleStorage};

  use pyth::state::{State as PythState};
  use pyth::price_info::{PriceInfoObject};

  use wormhole::state::{State as WormholeState};

  use switchboard_std::aggregator::{Aggregator};

  use library::utils::{handle_coin_vector, public_transfer_coin};

  use money_market::interest_rate_model::{InterestRateModelStorage};
  use money_market::ipx_money_market::{Self as money_market, MoneyMarketStorage};

  entry public fun accrue<T>(
    money_market_storage: &mut MoneyMarketStorage, 
    interest_rate_model_storage: &InterestRateModelStorage, 
    clock_object: &Clock
  ) {
    money_market::accrue<T>(money_market_storage, interest_rate_model_storage, clock_object);    
  }

  entry public fun accrue_suid(
    money_market_storage: &mut MoneyMarketStorage, 
    clock_object: &Clock
  ) {
    money_market::accrue_suid(money_market_storage, clock_object);
  }

  entry public fun deposit<T>(
    money_market_storage: &mut MoneyMarketStorage, 
    interest_rate_model_storage: &InterestRateModelStorage,
    ipx_storage: &mut IPXStorage, 
    clock_object: &Clock,
    asset_vector: vector<Coin<T>>,
    asset_value: u64,
    ctx: &mut TxContext
  ) {
      public_transfer_coin(
        money_market::deposit<T>(
          money_market_storage,
          interest_rate_model_storage, 
          ipx_storage,
          clock_object,
          handle_coin_vector<T>(asset_vector, asset_value, ctx),
          ctx
        ),
        tx_context::sender(ctx)
      );
  } 

  public fun withdraw<T>(
    money_market_storage: &mut MoneyMarketStorage, 
    interest_rate_model_storage: &InterestRateModelStorage,
    ipx_storage: &mut IPXStorage, 
    price_potatoes: vector<PricePotato>,
    clock_object: &Clock,
    shares_to_remove: u64,
    ctx: &mut TxContext
  ) {
    let (asset, ipx_coin) = money_market::withdraw<T>(
      money_market_storage,
      interest_rate_model_storage,
      ipx_storage,
      price_potatoes,
      clock_object,
      shares_to_remove,
      ctx
    );

    let sender = tx_context::sender(ctx);

    public_transfer_coin(asset, sender);
    public_transfer_coin(ipx_coin, sender);
  }

  public fun borrow<T>(
    money_market_storage: &mut MoneyMarketStorage, 
    interest_rate_model_storage: &InterestRateModelStorage,
    ipx_storage: &mut IPXStorage, 
    price_potatoes: vector<PricePotato>,
    clock_object: &Clock,
    borrow_value: u64,
    ctx: &mut TxContext    
  ) {
    let (asset, ipx_coin) = money_market::borrow<T>(
      money_market_storage,
      interest_rate_model_storage,
      ipx_storage,
      price_potatoes,
      clock_object,
      borrow_value,
      ctx
    );

    let sender = tx_context::sender(ctx);

    public_transfer_coin(asset, sender);
    public_transfer_coin(ipx_coin, sender);    
  }

  public fun repay<T>(
    money_market_storage: &mut MoneyMarketStorage, 
    interest_rate_model_storage: &InterestRateModelStorage,
    ipx_storage: &mut IPXStorage, 
    clock_object: &Clock,
    asset_vector: vector<Coin<T>>,
    asset_value: u64,
    principal_to_repay: u64,
    ctx: &mut TxContext   
  ) {

    let (extra_coin, ipx_coin) = money_market::repay<T>(
        money_market_storage,
        interest_rate_model_storage,
        ipx_storage,
        clock_object,
        handle_coin_vector<T>(asset_vector, asset_value, ctx),
        principal_to_repay,
        ctx
    );

    let sender = tx_context::sender(ctx);

    public_transfer_coin(extra_coin, sender);
    public_transfer_coin(ipx_coin, sender);
  }

  entry public fun enter_market<T>(money_market_storage: &mut MoneyMarketStorage, ctx: &mut TxContext) {
    money_market::enter_market<T>(money_market_storage, ctx);
  }

  public fun exit_market<T>(
    money_market_storage: &mut MoneyMarketStorage, 
    interest_rate_model_storage: &InterestRateModelStorage,
    price_potatoes: vector<PricePotato>,
    clock_object: &Clock,
    ctx: &mut TxContext
  ) {
    money_market::exit_market<T>(money_market_storage, interest_rate_model_storage, price_potatoes, clock_object, ctx);
  }

  public fun borrow_suid(
    money_market_storage: &mut MoneyMarketStorage,
    interest_rate_model_storage: &InterestRateModelStorage,
    ipx_storage: &mut IPXStorage,
    suid_storage: &mut SuiDollarStorage,
    price_potatoes: vector<PricePotato>,
    clock_object: &Clock,
    borrow_value: u64,
    ctx: &mut TxContext
  ) {
    let (coin_suid, coin_ipx) = money_market::borrow_suid(
      money_market_storage,
      interest_rate_model_storage,
      ipx_storage,
      suid_storage,
      price_potatoes,
      clock_object,
      borrow_value,
      ctx
    );

    let sender = tx_context::sender(ctx);

    public_transfer_coin(coin_suid, sender);
    public_transfer_coin(coin_ipx, sender);
  } 


  public fun repay_suid(
    money_market_storage: &mut MoneyMarketStorage, 
    ipx_storage: &mut IPXStorage, 
    suid_storage: &mut SuiDollarStorage,
    clock_object: &Clock,
    asset_vector: vector<Coin<SUID>>,
    asset_value: u64,
    principal_to_repay: u64,
    ctx: &mut TxContext 
  ) {

    let (extra_coin, ipx_coin) = money_market::repay_suid(
        money_market_storage,
        ipx_storage,
        suid_storage,
        clock_object,
        handle_coin_vector<SUID>(asset_vector, asset_value, ctx),
        principal_to_repay,
        ctx
    );

    let sender = tx_context::sender(ctx);

    public_transfer_coin(extra_coin, sender);
    public_transfer_coin(ipx_coin, sender);
  }

  entry public fun get_rewards<T>(
    money_market_storage: &mut MoneyMarketStorage, 
    interest_rate_model_storage: &InterestRateModelStorage,
    ipx_storage: &mut IPXStorage, 
    clock_object: &Clock,
    ctx: &mut TxContext 
  ) {
    public_transfer_coin(
      money_market::get_rewards<T>(
        money_market_storage,
        interest_rate_model_storage,
        ipx_storage,
        clock_object,
        ctx
      ),
      tx_context::sender(ctx)
    );
  }

  entry public fun get_all_rewards(
    money_market_storage: &mut MoneyMarketStorage, 
    interest_rate_model_storage: &InterestRateModelStorage,
    ipx_storage: &mut IPXStorage, 
    clock_object: &Clock,
    ctx: &mut TxContext 
  ) {
    public_transfer_coin(
      money_market::get_all_rewards(
        money_market_storage,
        interest_rate_model_storage,
        ipx_storage,
        clock_object,
        ctx
      ),
      tx_context::sender(ctx)
    );    
  }

  public fun liquidate<C, L>(
    money_market_storage: &mut MoneyMarketStorage,
    interest_rate_model_storage: &InterestRateModelStorage,
    ipx_storage: &mut IPXStorage,
    price_potatoes: vector<PricePotato>,
    clock_object: &Clock,
    asset_vector: vector<Coin<L>>,
    asset_value: u64,
    borrower: address,
    ctx: &mut TxContext
  ) { 
    public_transfer_coin(
      money_market::liquidate<C, L>(
      money_market_storage,
      interest_rate_model_storage,
      ipx_storage,
      price_potatoes,
      clock_object,
      handle_coin_vector<L>(asset_vector, asset_value, ctx),
      borrower,
      ctx
    ),
    tx_context::sender(ctx)
  );
   }

  public fun liquidate_suid<C>(
    money_market_storage: &mut MoneyMarketStorage,
    interest_rate_model_storage: &InterestRateModelStorage,
    ipx_storage: &mut IPXStorage,
    suid_storage: &mut SuiDollarStorage,
    price_potatoes: vector<PricePotato>,
    clock_object: &Clock,
    asset_vector: vector<Coin<SUID>>,
    asset_value: u64,
    borrower: address,
    ctx: &mut TxContext
  ) {
    public_transfer_coin(
      money_market::liquidate_suid<C>(
      money_market_storage,
      interest_rate_model_storage,
      ipx_storage,
      suid_storage,
      price_potatoes,
      clock_object,
      handle_coin_vector<SUID>(asset_vector, asset_value, ctx),
      borrower,
      ctx
    ),
    tx_context::sender(ctx)
  );
  }

  public fun get_prices(
    storage: &mut OracleStorage, 
    wormhole_state: &WormholeState,
    pyth_state: &PythState,
    bufs: vector<vector<u8>>,
    price_info_objects: &mut vector<PriceInfoObject>,
    pyth_fees: vector<Coin<SUI>>,
    clock_object: &Clock,
    switchboard_feeds: &vector<Aggregator>, 
    coin_names: vector<String>,
    ctx: &mut TxContext    
  ): vector<PricePotato> {
    let price_potatoes = vector::empty<PricePotato>();

    let length = vector::length(&coin_names);
    let index = 0;

    while (index < length) {
      
      let potato = ipx_oracle::get_price(
        storage,
        wormhole_state,
        pyth_state,
        vector::pop_back(&mut bufs),
        vector::borrow_mut(price_info_objects, index),
        vector::pop_back(&mut pyth_fees),
        clock_object,
        vector::borrow(switchboard_feeds, index),
        vector::pop_back(&mut coin_names),
        ctx        
      );

      vector::push_back(&mut price_potatoes, potato);

      index = index + 1;
    };

    vector::destroy_empty(pyth_fees);
    vector::destroy_empty(bufs);
    vector::destroy_empty(coin_names);

    price_potatoes
  }
}