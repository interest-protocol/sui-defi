#[test_only]
module interest_protocol::usdc {
    use std::option;

    use sui::url;
    use sui::coin::{Self, Coin};
    use sui::tx_context::{TxContext};
    use sui::transfer;
    use sui::object::{Self, UID};
    use sui::balance::{Self, Supply};

    struct USDC has drop {}

    struct Storage has key {
        id: UID,
        supply: Supply<USDC>
    }

      fun init(witness: USDC, ctx: &mut TxContext) {
      // Create the IPX governance token with 9 decimals
      let (treasury, metadata) = coin::create_currency<USDC>(
            witness, 
            6,
            b"USDC",
            b"USD Coin",
            b"USD Coin",
            option::some(url::new_unsafe_from_bytes(b"https://dev.interestprotocol.com/logo-blue.jpg")),
            ctx
        );
        
        transfer::freeze_object(metadata);
        transfer::share_object(Storage {
            id: object::new(ctx),
            supply: coin::treasury_into_supply(treasury)
        });
  }

  public fun mint(storage: &mut Storage, value: u64, ctx: &mut TxContext): Coin<USDC> {
    coin::from_balance(balance::increase_supply(&mut storage.supply, value), ctx)
  }

  #[test_only]
  public fun init_for_testing(ctx: &mut TxContext) {
      init(USDC {}, ctx);
  }
}

#[test_only]
module interest_protocol::usdt {
    use std::option;

    use sui::url;
    use sui::coin::{Self, Coin};
    use sui::tx_context::{TxContext};
    use sui::transfer;
    use sui::object::{Self, UID};
    use sui::balance::{Self, Supply};

    struct USDT has drop {}

    struct Storage has key {
        id: UID,
        supply: Supply<USDT>
    }

      fun init(witness: USDT, ctx: &mut TxContext) {
      // Create the IPX governance token with 9 decimals
      let (treasury, metadata) = coin::create_currency<USDT>(
            witness, 
            9,
            b"USDT",
            b"USD Tether",
            b"USD Tether",
            option::some(url::new_unsafe_from_bytes(b"https://dev.interestprotocol.com/logo-blue.jpg")),
            ctx
        );
        
        transfer::freeze_object(metadata);
        transfer::share_object(Storage {
            id: object::new(ctx),
            supply: coin::treasury_into_supply(treasury)
        });
  }

  public fun mint(storage: &mut Storage, value: u64, ctx: &mut TxContext): Coin<USDT> {
    coin::from_balance(balance::increase_supply(&mut storage.supply, value), ctx)
  }

  #[test_only]
  public fun init_for_testing(ctx: &mut TxContext) {
      init(USDT {}, ctx);
  }
}
