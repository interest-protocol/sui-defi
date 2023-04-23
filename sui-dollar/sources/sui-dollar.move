// Stable coin of Interest Protocol
module sui_dollar::suid {
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
  const ERROR_NO_ZERO_ADDRESS: u64 = 2;

  // OTW to create the Sui Stable SuiDollar currency
  struct SUID has drop {}

  // Shared object
  struct SuiDollarStorage has key {
    id: UID,
    supply: Supply<SUID>,
    minters: VecSet<ID> // List of publishers that are allowed to mint SUID
  }

  // The owner of this object can add and remove minters
  struct SuiDollarAdminCap has key {
    id: UID
  }

  // Events 

  struct MinterAdded has copy, drop {
    id: ID
  }

  struct MinterRemoved has copy, drop {
    id: ID
  }

  struct NewAdmin has copy, drop {
    admin: address
  }

  fun init(witness: SUID, ctx: &mut TxContext) {
      // Create the SUID stable coin
      let (treasury, metadata) = coin::create_currency<SUID>(
            witness, 
            9,
            b"SUID",
            b"Sui Dollar",
            b"Interest Protocol Sui Stable Coin",
            // TODO need to update the logo URL to put on Arweave
            option::some(url::new_unsafe_from_bytes(b"https://www.interestprotocol.com")),
            ctx
        );

      // Transform the treasury_cap into a supply struct to allow this contract to mint/burn SUID
      let supply = coin::treasury_into_supply(treasury);

      // Share the SuiDollarStorage Object with the Sui network
      transfer::share_object(
        SuiDollarStorage {
          id: object::new(ctx),
          supply,
          minters: vec_set::empty()
        }
      );

      // Send the AdminCap to the deployer
      transfer::transfer(
        SuiDollarAdminCap {
          id: object::new(ctx)
        },
        tx_context::sender(ctx)
      );

      // Freeze the metadata object, since we cannot update without the TreasuryCap
      transfer::public_freeze_object(metadata);
  }

  /**
  * @dev Only packages can mint dinero by passing the storage publisher
  * @param storage The SuiDollarStorage
  * @param publisher The Publisher object of the package who wishes to mint SuiDollar
  * @return Coin<SUID> New created SUID coin
  */
  public fun mint(storage: &mut SuiDollarStorage, publisher: &Publisher, value: u64, ctx: &mut TxContext): Coin<SUID> {
    assert!(is_minter(storage, object::id(publisher)), ERROR_NOT_ALLOWED_TO_MINT);

    coin::from_balance(balance::increase_supply(&mut storage.supply, value), ctx)
  }

  /**
  * @dev This function allows anyone to burn their own SUID.
  * @param storage The SuiDollarStorage shared object
  * @param coin_dnr The dinero coin that will be burned
  */
  public fun burn(storage: &mut SuiDollarStorage, coin_dnr: Coin<SUID>): u64 {
    balance::decrease_supply(&mut storage.supply, coin::into_balance(coin_dnr))
  }

  /**
  * @dev Utility function to transfer Coin<SUID>
  * @param The coin to transfer
  * @param recipient The address that will receive the Coin<SUID>
  */
  public entry fun transfer(coin_dnr: coin::Coin<SUID>, recipient: address) {
    transfer::public_transfer(coin_dnr, recipient);
  }

  /**
  * It allows anyone to know the total value in existence of SUID
  * @storage The shared SuiDollarStorage
  * @return u64 The total value of SUID in existence
  */
  public fun total_supply(storage: &SuiDollarStorage): u64 {
    balance::supply_value(&storage.supply)
  }

  /**
  * @dev It allows the holder of the {SuiDollarAdminCap} to add a minter. 
  * @param _ The SuiDollarAdminCap to guard this function 
  * @param storage The SuiDollarStorage shared object
  * @param publisher The package that owns this publisher will be able to mint it
  *
  * It emits the MinterAdded event with the {ID} of the {Publisher}
  *
  */
  entry public fun add_minter(_: &SuiDollarAdminCap, storage: &mut SuiDollarStorage, id: ID) {
    vec_set::insert(&mut storage.minters, id);
    emit(
      MinterAdded {
        id
      }
    );
  }

  /**
  * @dev It allows the holder of the {SuiDollarAdminCap} to remove a minter. 
  * @param _ The SuiDollarAdminCap to guard this function 
  * @param storage The SuiDollarStorage shared object
  * @param publisher The package that will no longer be able to mint SuiDollar
  *
  * It emits the  MinterRemoved event with the {ID} of the {Publisher}
  *
  */
  entry public fun remove_minter(_: &SuiDollarAdminCap, storage: &mut SuiDollarStorage, id: ID) {
    vec_set::remove(&mut storage.minters, &id);
    emit(
      MinterRemoved {
        id
      }
    );
  } 

 /**
  * @dev It gives the admin rights to the recipient. 
  * @param admin_cap The SuiDollarAdminCap that will be transferred
  * @recipient the new admin address
  *
  * It emits the NewAdmin event with the new admin address
  *
  */
  entry public fun transfer_admin(admin_cap: SuiDollarAdminCap, recipient: address) {
    assert!(recipient != @0x0, ERROR_NO_ZERO_ADDRESS);
    transfer::transfer(admin_cap, recipient);

    emit(NewAdmin {
      admin: recipient
    });
  } 

  /**
  * @dev It indicates if a package has the right to mint SuiDollar
  * @param storage The SuiDollarStorage shared object
  * @param publisher of the package 
  * @return bool true if it can mint SuiDollar
  */
  public fun is_minter(storage: &SuiDollarStorage, id: ID): bool {
    vec_set::contains(&storage.minters, &id)
  }

  // Test only functions
  #[test_only]
  public fun init_for_testing(ctx: &mut TxContext) {
    init(SUID {}, ctx);
  }

  #[test_only]
  public fun mint_for_testing(storage: &mut SuiDollarStorage, value: u64, ctx: &mut TxContext): Coin<SUID> {
    coin::from_balance(balance::increase_supply(&mut storage.supply, value), ctx)
  }
}