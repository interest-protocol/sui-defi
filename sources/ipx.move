module interest_protocol::ipx {
  use std::option;

  use sui::object::{Self, UID};
  use sui::tx_context::{TxContext};
  use sui::balance::{Self, Supply};
  use sui::transfer;
  use sui::coin::{Self, Coin};
  use sui::url;

  friend interest_protocol::whirpool;
  friend interest_protocol::master_chef;
  friend interest_protocol::interface;

  const IPX_PRE_MINT_AMOUNT: u64 = 600000000000000000; // 600M 60% of the supply

  struct IPX has drop {}

  struct IPXStorage has key {
    id: UID,
    supply: Supply<IPX>
  }

  fun init(witness: IPX, ctx: &mut TxContext) {
      // Create the IPX governance token with 9 decimals
      let (treasury, metadata) = coin::create_currency<IPX>(
            witness, 
            9,
            b"IPX",
            b"Interest Protocol Token",
            b"The governance token of Interest Protocol",
            option::some(url::new_unsafe_from_bytes(b"https://www.interestprotocol.com")),
            ctx
        );
      // Transform the treasury_cap into a supply struct to allow this contract to mint/burn DNR
      let supply = coin::treasury_into_supply(treasury);

      // Pre-mint 60% of the supply to distribute
      transfer::transfer(
        coin::from_balance(
          balance::increase_supply(&mut supply, IPX_PRE_MINT_AMOUNT), ctx
        ),
        @dev
      );

      transfer::share_object(
        IPXStorage {
          id: object::new(ctx),
          supply
        }
      );

      // Freeze the metadata object
      transfer::freeze_object(metadata);
  }

  public(friend) fun mint(storage: &mut IPXStorage, value: u64, ctx: &mut TxContext): Coin<IPX> {
    coin::from_balance(balance::increase_supply(&mut storage.supply, value), ctx)
  }

  public(friend) fun burn(storage: &mut IPXStorage, coin_dnr: Coin<IPX>): u64 {
    balance::decrease_supply(&mut storage.supply, coin::into_balance(coin_dnr))
  }

  public entry fun transfer(c: coin::Coin<IPX>, recipient: address) {
    transfer::transfer(c, recipient);
  }

  #[test_only]
  public fun init_for_testing(ctx: &mut TxContext) {
    init(IPX {}, ctx);
  }
}