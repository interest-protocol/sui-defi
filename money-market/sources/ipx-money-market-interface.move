module money_market::ipx_money_market_interface {

  use sui::coin::{Coin};
  use sui::clock::{Clock};
  use sui::tx_context::{Self, TxContext};

  use ipx::ipx::{IPXStorage};

  use sui_dollar::suid::{SUID, SuiDollarStorage};

  use library::utils::{handle_coin_vector, public_transfer};

  use oracle::ipx_oracle::{Price as PricePotato};

  use money_market::interest_rate_model::{InterestRateModelStorage};
  use money_market::ipx_money_market::{Self as money_market, MoneyMarketStorage};

  entry fun accrue<T>(
    money_market_storage: &mut MoneyMarketStorage, 
    interest_rate_model_storage: &InterestRateModelStorage, 
    clock_object: &Clock
  ) {
    money_market::accrue<T>(money_market_storage, interest_rate_model_storage, clock_object);    
  }

  entry fun accrue_suid(
    money_market_storage: &mut MoneyMarketStorage, 
    clock_object: &Clock
  ) {
    money_market::accrue_suid(money_market_storage, clock_object);
  }

  entry fun deposit<T>(
    money_market_storage: &mut MoneyMarketStorage, 
    interest_rate_model_storage: &InterestRateModelStorage,
    ipx_storage: &mut IPXStorage, 
    clock_object: &Clock,
    asset_vector: vector<Coin<T>>,
    asset_value: u64,
    ctx: &mut TxContext
  ) {
      public_transfer(
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

  entry fun withdraw<T>(
    money_market_storage: &mut MoneyMarketStorage, 
    interest_rate_model_storage: &InterestRateModelStorage,
    ipx_storage: &mut IPXStorage, 
    price_potatoes: vector<PricePotato>,
    clock_object: &Clock,
    shares_to_remove: u64,
    ctx: &mut TxContext
  ) {
    let (asset, coin_ipx) = money_market::withdraw<T>(
      money_market_storage,
      interest_rate_model_storage,
      ipx_storage,
      price_potatoes,
      clock_object,
      shares_to_remove,
      ctx
    );

    let sender = tx_context::sender(ctx);

    public_transfer(asset, sender);
    public_transfer(coin_ipx, sender);
  }

  entry fun borrow<T>(
    money_market_storage: &mut MoneyMarketStorage, 
    interest_rate_model_storage: &InterestRateModelStorage,
    ipx_storage: &mut IPXStorage, 
    price_potatoes: vector<PricePotato> ,
    clock_object: &Clock,
    borrow_value: u64,
    ctx: &mut TxContext    
  ) {
    let (asset, coin_ipx) = money_market::borrow<T>(
      money_market_storage,
      interest_rate_model_storage,
      ipx_storage,
      price_potatoes,
      clock_object,
      borrow_value,
      ctx
    );

    let sender = tx_context::sender(ctx);

    public_transfer(asset, sender);
    public_transfer(coin_ipx, sender);    
  }

  entry fun repay<T>(
    money_market_storage: &mut MoneyMarketStorage, 
    interest_rate_model_storage: &InterestRateModelStorage,
    ipx_storage: &mut IPXStorage, 
    clock_object: &Clock,
    asset_vector: vector<Coin<T>>,
    asset_value: u64,
    principal_to_repay: u64,
    ctx: &mut TxContext   
  ) {
    public_transfer(
      money_market::repay<T>(
        money_market_storage,
        interest_rate_model_storage,
        ipx_storage,
        clock_object,
        handle_coin_vector<T>(asset_vector, asset_value, ctx),
        principal_to_repay,
        ctx
        ),
      tx_context::sender(ctx)  
    ); 
  }

  entry fun enter_market<T>(money_market_storage: &mut MoneyMarketStorage, ctx: &mut TxContext) {
    money_market::enter_market<T>(money_market_storage, ctx);
  }

  entry fun exit_market<T>(
    money_market_storage: &mut MoneyMarketStorage, 
    interest_rate_model_storage: &InterestRateModelStorage,
    price_potatoes: vector<PricePotato>,
    clock_object: &Clock,
    ctx: &mut TxContext
  ) {
    money_market::exit_market<T>(money_market_storage, interest_rate_model_storage, price_potatoes, clock_object, ctx);
  }

  entry fun borrow_suid(
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

    public_transfer(coin_suid, sender);
    public_transfer(coin_ipx, sender);
  } 


  entry fun repay_suid(
    money_market_storage: &mut MoneyMarketStorage, 
    ipx_storage: &mut IPXStorage, 
    suid_storage: &mut SuiDollarStorage,
    clock_object: &Clock,
    asset_vector: vector<Coin<SUID>>,
    asset_value: u64,
    principal_to_repay: u64,
    ctx: &mut TxContext 
  ) {
    public_transfer(
      money_market::repay_suid(
        money_market_storage,
        ipx_storage,
        suid_storage,
        clock_object,
        handle_coin_vector<SUID>(asset_vector, asset_value, ctx),
        principal_to_repay,
        ctx
      ),
      tx_context::sender(ctx)
    );
  }

  entry fun get_rewards<T>(
    money_market_storage: &mut MoneyMarketStorage, 
    interest_rate_model_storage: &InterestRateModelStorage,
    ipx_storage: &mut IPXStorage, 
    clock_object: &Clock,
    ctx: &mut TxContext 
  ) {
    public_transfer(
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

  entry fun get_all_rewards(
    money_market_storage: &mut MoneyMarketStorage, 
    interest_rate_model_storage: &InterestRateModelStorage,
    ipx_storage: &mut IPXStorage, 
    clock_object: &Clock,
    ctx: &mut TxContext 
  ) {
    public_transfer(
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

  entry fun liquidate<C, L>(
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
    money_market::liquidate<C, L>(
      money_market_storage,
      interest_rate_model_storage,
      ipx_storage,
      price_potatoes,
      clock_object,
      handle_coin_vector<L>(asset_vector, asset_value, ctx),
      borrower,
      ctx
    );
   }

  entry fun liquidate_suid<C>(
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
    );
  }
}