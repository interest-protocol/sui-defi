// Stable coin of Interest Protocol
module interest_protocol::dnr {
  use std::option;

  use sui::object::{Self, UID, ID};
  use sui::tx_context::{TxContext};
  use sui::balance::{Self, Supply};
  use sui::transfer;
  use sui::coin::{Self, Coin};
  use sui::url;
  use sui::package::{Publisher};
  use sui::tx_context;
  use sui::vec_set::{Self, VecSet};
  use sui::event::{emit};

  const ERROR_NOT_ALLOWED_TO_MINT: u64 = 1;

  // OTW to create the Sui Stable Dinero currency
  struct DNR has drop {}

  // Shared object
  struct DineroStorage has key {
    id: UID,
    supply: Supply<DNR>,
    minters: VecSet<ID> // List of publishers that are allowed to mint DNR
  }

  // The owner of this object can add and remove minters
  struct DineroAdminCap has key {
    id: UID
  }

  // Events 

  struct MinterAdded has copy, drop {
    id: ID
  }

  struct MinterRemoved has copy, drop {
    id: ID
  }

  fun init(witness: DNR, ctx: &mut TxContext) {
      // Create the DNR stable coin
      let (treasury, metadata) = coin::create_currency<DNR>(
            witness, 
            9,
            b"sDNR",
            b"Sui Stable Dinero",
            b"Interest Protocol Sui Stable Coin",
            option::some(url::new_unsafe_from_bytes(b"https://www.interestprotocol.com")), // TODO need to update the logo URL
            ctx
        );

      // Transform the treasury_cap into a supply struct to allow this contract to mint/burn DNR
      let supply = coin::treasury_into_supply(treasury);

      // Share the DineroStorage Object with the Sui network
      transfer::share_object(
        DineroStorage {
          id: object::new(ctx),
          supply,
          minters: vec_set::empty()
        }
      );

      // Send the AdminCap to the deployer
      transfer::transfer(
        DineroAdminCap {
          id: object::new(ctx)
        },
        tx_context::sender(ctx)
      );

      // Freeze the metadata object, since we cannot update without the TreasuryCap
      transfer::public_freeze_object(metadata);
  }

  /**
  * @dev Only packages can mint dinero by passing the storage publisher
  * @param storage The DineroStorage
  * @param publisher The Publisher object of the package who wishes to mint Dinero
  * @return Coin<DNR> New created DNR coin
  */
  public fun mint(storage: &mut DineroStorage, publisher: &Publisher, value: u64, ctx: &mut TxContext): Coin<DNR> {
    assert!(is_minter(storage, object::id(publisher)), ERROR_NOT_ALLOWED_TO_MINT);

    coin::from_balance(balance::increase_supply(&mut storage.supply, value), ctx)
  }

  /**
  * @dev This function allows anyone to burn their own DNR.
  * @param storage The DineroStorage shared object
  * @param coin_dnr The dinero coin that will be burned
  */
  public fun burn(storage: &mut DineroStorage, coin_dnr: Coin<DNR>): u64 {
    balance::decrease_supply(&mut storage.supply, coin::into_balance(coin_dnr))
  }

  /**
  * @dev Utility function to transfer Coin<DNR>
  * @param The coin to transfer
  * @param recipient The address that will receive the Coin<DNR>
  */
  public entry fun transfer(coin_dnr: coin::Coin<DNR>, recipient: address) {
    transfer::public_transfer(coin_dnr, recipient);
  }

  /**
  * It allows anyone to know the total value in existence of DNR
  * @storage The shared DineroStorage
  * @return u64 The total value of DNR in existence
  */
  public fun total_supply(storage: &DineroStorage): u64 {
    balance::supply_value(&storage.supply)
  }

  /**
  * @dev It allows the holder of the {DineroAdminCap} to add a minter. 
  * @param _ The DineroAdminCap to guard this function 
  * @param storage The DineroStorage shared object
  * @param publisher The package that owns this publisher will be able to mint it
  *
  * It emits the MinterAdded event with the {ID} of the {Publisher}
  *
  */
  entry public fun add_minter(_: &DineroAdminCap, storage: &mut DineroStorage, id: ID) {
    vec_set::insert(&mut storage.minters, id);
    emit(
      MinterAdded {
        id
      }
    );
  }

  /**
  * @dev It allows the holder of the {DineroAdminCap} to remove a minter. 
  * @param _ The DineroAdminCap to guard this function 
  * @param storage The DineroStorage shared object
  * @param publisher The package that will no longer be able to mint Dinero
  *
  * It emits the  MinterRemoved event with the {ID} of the {Publisher}
  *
  */
  entry public fun remove_minter(_: &DineroAdminCap, storage: &mut DineroStorage, id: ID) {
    vec_set::remove(&mut storage.minters, &id);
    emit(
      MinterRemoved {
        id
      }
    );
  } 

  /**
  * @dev It indicates if a package has the right to mint Dinero
  * @param storage The DineroStorage shared object
  * @param publisher of the package 
  * @return bool true if it can mint Dinero
  */
  public fun is_minter(storage: &DineroStorage, id: ID): bool {
    vec_set::contains(&storage.minters, &id)
  }

  // Test only functions
  #[test_only]
  public fun init_for_testing(ctx: &mut TxContext) {
    init(DNR {}, ctx);
  }

  #[test_only]
  public fun mint_for_testing(storage: &mut DineroStorage, value: u64, ctx: &mut TxContext): Coin<DNR> {
    coin::from_balance(balance::increase_supply(&mut storage.supply, value), ctx)
  }
}