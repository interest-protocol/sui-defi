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

  use library::merkle_proof;

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

  public fun get_airdrop(
    storage: &mut AirdropStorage, 
    clock_object: &Clock,
    proof: vector<vector<u8>>, 
    amount: u64, 
    ctx: &mut TxContext
  ): Coin<IPX> {
    assert!(storage.start != 0, ERROR_NOT_STARTED);
    assert!(!vector::is_empty(&storage.root), ERROR_NO_ROOT);

    let sender = tx_context::sender(ctx);
    let payload = bcs::to_bytes(&sender);
    let start = storage.start;

    vector::append(&mut payload, bcs::to_bytes(&amount));

    let leaf = hash::sha3_256(payload);
    
    assert!(merkle_proof::verify(&proof, storage.root, leaf), ERROR_INVALID_PROOF);

    let account = get_mut_account(storage, sender);

    // user already got the entire airdrop
    assert!(amount > account.released, ERROR_ALL_CLAIMED);

    let released_amount = vesting_schedule(start, amount, clock::timestamp_ms(clock_object));

    let amount_to_send = released_amount - account.released;
    account.released = account.released + amount_to_send;
    // sanity check
    assert!(account.released <= amount, ERROR_ALL_CLAIMED);

    coin::take(&mut storage.balance, amount_to_send, ctx)
  }

  entry fun airdrop(
    storage: &mut AirdropStorage, 
    clock_object: &Clock,
    proof: vector<vector<u8>>, 
    amount: u64, 
    ctx: &mut TxContext
  ) {
    transfer::public_transfer(
      get_airdrop(
        storage,
        clock_object,
        proof,
        amount,
        ctx
      ),
      tx_context::sender(ctx));
  }

  fun get_mut_account(storage: &mut AirdropStorage, sender: address): &mut Account {
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

  entry public fun start(_: &AirdropAdminCap, storage: &mut AirdropStorage, root: vector<u8>, coin_ipx: Coin<IPX>, start_time: u64) {
    storage.root = root;
    balance::join(&mut storage.balance, coin::into_balance(coin_ipx));
    storage.start = start_time;
  }

  public fun read_account(storage: &AirdropStorage, user: address): u64 {
    if (!vec_map::contains(&storage.accounts, &user)) return 0;

    let account = vec_map::get(&storage.accounts, &user);
    account.released
  }

  #[test_only]
  public fun init_for_testing(ctx: &mut TxContext) {
    init(ctx);
  }

  #[test_only]
  public fun read_storage(storage: &AirdropStorage): (u64, vector<u8>, u64) {
    (balance::value(&storage.balance), storage.root, storage.start)
  }

  #[test_only]
  public fun get_duration():u64 {
    THIRTY_DAYS_IN_MS
  }
}