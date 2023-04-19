#[test_only]
module library::usdc {
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
        
        transfer::public_freeze_object(metadata);
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
module library::usdt {
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
        
        transfer::public_freeze_object(metadata);
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

#[test_only]
module library::btc {
    use std::option;

    use sui::url;
    use sui::coin::{Self, Coin};
    use sui::tx_context::{TxContext};
    use sui::transfer;
    use sui::object::{Self, UID};
    use sui::balance::{Self, Supply};

    struct BTC has drop {}

    struct Storage has key {
        id: UID,
        supply: Supply<BTC>
    }

      fun init(witness: BTC, ctx: &mut TxContext) {
      // Create the IPX governance token with 9 decimals
      let (treasury, metadata) = coin::create_currency<BTC>(
            witness, 
            9,
            b"BTC",
            b"Bitcoin",
            b"Bitcoin",
            option::some(url::new_unsafe_from_bytes(b"https://dev.interestprotocol.com/logo-blue.jpg")),
            ctx
        );
        
        transfer::public_share_object(metadata);
        transfer::share_object(Storage {
            id: object::new(ctx),
            supply: coin::treasury_into_supply(treasury)
        });
  }

  public fun mint(storage: &mut Storage, value: u64, ctx: &mut TxContext): Coin<BTC> {
    coin::from_balance(balance::increase_supply(&mut storage.supply, value), ctx)
  }

  #[test_only]
  public fun init_for_testing(ctx: &mut TxContext) {
      init(BTC {}, ctx);
  }
}

#[test_only]
module library::eth {
    use std::option;

    use sui::url;
    use sui::coin::{Self, Coin};
    use sui::tx_context::{TxContext};
    use sui::transfer;
    use sui::object::{Self, UID};
    use sui::balance::{Self, Supply};

    struct ETH has drop {}

    struct Storage has key {
        id: UID,
        supply: Supply<ETH>
    }

      fun init(witness: ETH, ctx: &mut TxContext) {
      // Create the IPX governance token with 9 decimals
      let (treasury, metadata) = coin::create_currency<ETH>(
            witness, 
            8,
            b"ETH",
            b"ETHER",
            b"ETHER",
            option::some(url::new_unsafe_from_bytes(b"https://dev.interestprotocol.com/logo-blue.jpg")),
            ctx
        );
        
        transfer::public_share_object(metadata);
        transfer::share_object(Storage {
            id: object::new(ctx),
            supply: coin::treasury_into_supply(treasury)
        });
  }

  public fun mint(storage: &mut Storage, value: u64, ctx: &mut TxContext): Coin<ETH> {
    coin::from_balance(balance::increase_supply(&mut storage.supply, value), ctx)
  }

  #[test_only]
  public fun init_for_testing(ctx: &mut TxContext) {
      init(ETH {}, ctx);
  }
}

#[test_only]
module library::ada {
    use std::option;

    use sui::url;
    use sui::coin::{Self, Coin};
    use sui::tx_context::{TxContext};
    use sui::transfer;
    use sui::object::{Self, UID};
    use sui::balance::{Self, Supply};

    struct ADA has drop {}

    struct Storage has key {
        id: UID,
        supply: Supply<ADA>
    }

      fun init(witness: ADA, ctx: &mut TxContext) {
      // Create the IPX governance token with 9 decimals
      let (treasury, metadata) = coin::create_currency<ADA>(
            witness, 
            7,
            b"ADA",
            b"Cardano",
            b"Cardano",
            option::some(url::new_unsafe_from_bytes(b"https://dev.interestprotocol.com/logo-blue.jpg")),
            ctx
        );
        
        transfer::public_share_object(metadata);
        transfer::share_object(Storage {
            id: object::new(ctx),
            supply: coin::treasury_into_supply(treasury)
        });
  }

  public fun mint(storage: &mut Storage, value: u64, ctx: &mut TxContext): Coin<ADA> {
    coin::from_balance(balance::increase_supply(&mut storage.supply, value), ctx)
  }

  #[test_only]
  public fun init_for_testing(ctx: &mut TxContext) {
      init(ADA {}, ctx);
  }
}