module airdrop::core {
  use std::vector;
  use std::hash;
  
  use sui::object::{Self, UID};
  use sui::balance::{Self, Balance};
  use sui::coin::{Self, Coin};
  use sui::tx_context::{Self, TxContext};
  use sui::transfer;
  use sui::clock::{Self, Clock};
  use sui::vec_map::{Self, VecMap};
  use sui::bcs;

  use ipx::ipx::{IPX};

  use movemate::merkle_proof;

  const THIRTY_DAYS_IN_MS: u64 = 2592000000;

  const ERROR_INVALID_PROOF: u64 = 0;
  const ERROR_ALL_CLAIMED: u64 = 1;
  const ERROR_NOT_STARTED: u64 = 2;
  const ERROR_NO_ROOT: u64 = 3;

  struct AirdropAdminCap has key {
    id: UID
  }

  struct Account has store {
    released: u64
  }

  struct AirdropStorage has key { 
    id: UID,
    balance: Balance<IPX>,
    root: vector<u8>,
    start: u64,
    accounts: VecMap<address, Account>
  }

  fun init(ctx: &mut TxContext) {
    transfer::transfer(
      AirdropAdminCap {
        id: object::new(ctx)
      },
      tx_context::sender(ctx)
    );

    transfer::share_object(
      AirdropStorage {
        id: object::new(ctx),
        balance: balance::zero<IPX>(),
        root: vector::empty(),
        start: 0,
        accounts: vec_map::empty()
      }
    );
  }

  entry fun get_airdrop(
    storage: &mut AirdropStorage, 
    clock_object: &Clock,
    proof: vector<vector<u8>>, 
    amount: u64, 
    ctx: &mut TxContext
  ) {
    assert!(storage.start != 0, ERROR_NOT_STARTED);
    assert!(!vector::is_empty(&storage.root), ERROR_NO_ROOT);

    let sender = tx_context::sender(ctx);
    let payload = bcs::to_bytes(&sender);
    let start = storage.start;

    vector::append(&mut payload, bcs::to_bytes(&amount));
    let leaf = hash::sha2_256(payload);
    assert!(merkle_proof::verify(&proof, storage.root, leaf), ERROR_INVALID_PROOF);

    let account = get_account(storage, sender);

    // user already got the entire airdrop
    assert!(amount > account.released, ERROR_ALL_CLAIMED);

    let released_amount = vesting_schedule(start, amount, clock::timestamp_ms(clock_object));

    let amount_to_send = released_amount - account.released;
    account.released = account.released + amount_to_send;
    // sanity check
    assert!(account.released <= amount, ERROR_ALL_CLAIMED);

    transfer::transfer(coin::take(&mut storage.balance, amount_to_send, ctx), sender);
  }

  fun get_account(storage: &mut AirdropStorage, sender: address): &mut Account {
    if (!vec_map::contains(&storage.accounts, &sender)) {
      vec_map::insert(&mut storage.accounts, sender, Account { released: 0 });
    };

    vec_map::get_mut(&mut storage.accounts, &sender)
  }

  fun vesting_schedule(start: u64, total_allocation: u64, timestamp: u64): u64 {
        if (timestamp < start) return 0;
        if (timestamp > start + THIRTY_DAYS_IN_MS) return total_allocation;
        (total_allocation * (timestamp - start)) / THIRTY_DAYS_IN_MS
  }

  entry fun start(_: &AirdropAdminCap, storage: &mut AirdropStorage, root: vector<u8>, coin_ipx: Coin<IPX>, clock_object: &Clock) {
    storage.root = root;
    balance::join(&mut storage.balance, coin::into_balance(coin_ipx));
    storage.start = clock::timestamp_ms(clock_object);
  }
}