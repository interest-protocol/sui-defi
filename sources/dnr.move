module interest_protocol::dnr {
  use std::option;

  use sui::object::{Self, UID};
  use sui::tx_context::{TxContext};
  use sui::balance::{Self, Supply};
  use sui::transfer;
  use sui::coin::{Self, Coin};
  use sui::url;
  use sui::event;

  use interest_protocol::utils::{get_epochs_per_year};

  friend interest_protocol::whirpool;

  const INITIAL_INTEREST_RATE_PER_YEAR: u64 = 20000000; // 2% a year
  const MAX_INTEREST_RATE_PER_YEAR: u64 = 150000000; // 15% a year

  const ERROR_INTEREST_RATE_TOO_HIGH: u64 = 1;

  struct DNR has drop {}

  struct DineroStorage has key {
    id: UID,
    supply: Supply<DNR>,
    interest_rate_per_epoch: u64
  }

  struct Update_Interest_Rate has drop, copy {
    old_value: u64,
    new_value: u64
  }

  fun init(witness: DNR, ctx: &mut TxContext) {
      // Create the DNR stable coin
      let (treasury, metadata) = coin::create_currency<DNR>(
            witness, 
            9,
            b"DNR",
            b"Dinero",
            b"Interest Protocol Stable Coin",
            option::some(url::new_unsafe_from_bytes(b"https://www.interestprotocol.com")),
            ctx
        );

      // Transform the treasury_cap into a supply struct to allow this contract to mint/burn DNR
      let supply = coin::treasury_into_supply(treasury);

      transfer::share_object(
        DineroStorage {
          id: object::new(ctx),
          supply,
          interest_rate_per_epoch: INITIAL_INTEREST_RATE_PER_YEAR / get_epochs_per_year()
        }
      );

      // Freeze the metadata object
      transfer::freeze_object(metadata);
  }

  public(friend) fun mint(storage: &mut DineroStorage, value: u64, ctx: &mut TxContext): Coin<DNR> {
    coin::from_balance(balance::increase_supply(&mut storage.supply, value), ctx)
  }

  public(friend) fun burn(storage: &mut DineroStorage, coin_dnr: Coin<DNR>): u64 {
    balance::decrease_supply(&mut storage.supply, coin::into_balance(coin_dnr))
  }

  public(friend) fun update_interest_rate_per_epoch(storage: &mut DineroStorage, new_interest_rate: u64) {
    assert!(MAX_INTEREST_RATE_PER_YEAR >= new_interest_rate, ERROR_INTEREST_RATE_TOO_HIGH);
    event::emit(
      Update_Interest_Rate {
        old_value: storage.interest_rate_per_epoch,
        new_value: new_interest_rate
      }
    );
    storage.interest_rate_per_epoch = new_interest_rate / get_epochs_per_year();
  }

  public fun get_interest_rate_per_epoch(storage: &DineroStorage): u64 {
    storage.interest_rate_per_epoch
  }

  public entry fun transfer(c: coin::Coin<DNR>, recipient: address) {
    transfer::transfer(c, recipient);
  }

  #[test_only]
  public fun init_for_testing(ctx: &mut TxContext) {
    init(DNR {}, ctx);
  }
}