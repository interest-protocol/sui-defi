module launchpad::presale {
  use std::hash;

  use sui::object::{Self, UID, ID};
  use sui::object_bag::{Self, ObjectBag};
  use sui::vec_map::{Self, VecMap};
  use sui::balance::{Self, Balance};
  use sui::sui::{SUI};
  use sui::tx_context::{Self, TxContext};
  use sui::transfer;
  use sui::coin::{Self, Coin};
  use sui::clock::{Self, Clock};
  use sui::event::{emit};
  use sui::bcs;

  use library::merkle_proof;
  use library::math::{d_fmul};

  const ONE_HOUR_IN_MS: u64 = 3600000;

  const ERROR_ACCOUNT_ALREADY_CREATED_PRESALE: u64 = 0;
  const ERROR_INVALID_FEE: u64 = 1;
  const ERROR_INVALID_START_TIME: u64 = 2;
  const ERROR_INVALID_END_TIME: u64 = 3;
  const ERROR_INVALID_SOFT_CAP: u64 = 4;
  const ERROR_INVALID_MAX_AMOUNT_PER_USER: u64 = 5;
  const ERROR_INVALID_ADMIN: u64 = 6;
  const ERROR_HAS_NOT_STARTED: u64 = 7;
  const ERROR_HAS_ENDED: u64 = 8;
  const ERROR_NOT_WHITELISTED: u64 = 9;
  const ERROR_MAX_BUY_REACHED: u64 = 10;
  const ERROR_INVALID_BUY_AMOUNT: u64 = 11;
  const ERROR_HAS_NOT_ENDED: u64 = 12;
  const ERROR_PRESALE_FAILED: u64 = 13;
  const ERROR_HARD_CAP_REACHED: u64 = 14;

  struct Amount has store {
    value: u64
  }

  struct Presale<phantom T> has key, store {
    id: UID,
    balance: Balance<T>,
    soft_cap: u64,
    hard_cap: u64,
    min_amount_per_user: u64,
    max_amount_per_user: u64,
    start_time: u64,
    end_time: u64,
    first_release_percent: u64,
    cycle_length: u64,
    last_cycle_timestamp: u64,
    cycle_release_percent: u64,
    owner: address,
    root: vector<u8>,
    buyers: VecMap<address, Amount>,
    first_claim: bool,
    total_raised_amount: u64
  }

  struct PresaleAdminCap has key {
    id: UID
  }

  struct Storage has key {
    id: UID,
    sales: ObjectBag,
    fee_balance: Balance<SUI>,
    fee_amount: u64,
    treasury: address
  }

  // Events

  struct PresaleCreated<phantom T> has copy, drop {
    owner: address,
    id: ID,
    start_time: u64,
    hard_cap: u64
  }

  struct FeeValueUpdated has copy, drop {
    new_value: u64
  }

  struct TreasuryUpdated has copy, drop {
    new_treasury: address
  }

  struct BuyPresale<phantom T> has copy, drop {
    id: ID,
    buyer: address, 
    amount: u64
  }

  fun init(ctx: &mut TxContext) {
    
    transfer::share_object(
      Storage {
        id: object::new(ctx),
        sales: object_bag::new(ctx),
        fee_balance: balance::zero<SUI>(),
        fee_amount: 10000000000, // 10 SUI
        treasury: @treasury
      }
    );

    transfer::transfer(PresaleAdminCap { id: object::new(ctx) }, tx_context::sender(ctx));
  }

  entry public fun create_presale<T>(
    storage: &mut Storage,
    clock_object: &Clock,
    fee: Coin<SUI>,
    soft_cap: u64,
    hard_cap: u64,
    min_amount_per_user: u64,
    max_amount_per_user: u64,
    start_time: u64,
    end_time: u64,
    first_release_percent: u64,
    cycle_length: u64,
    last_cycle_timestamp: u64,
    cycle_release_percent: u64,
    root: vector<u8>,
    ctx: &mut TxContext
  ) {
    assert!(coin::value(&fee)>= storage.fee_amount, ERROR_INVALID_FEE);
    balance::join(&mut storage.fee_balance, coin::into_balance(fee));

    assert!(start_time >= clock::timestamp_ms(clock_object) + ONE_HOUR_IN_MS, ERROR_INVALID_START_TIME);
    assert!(end_time >= start_time + ONE_HOUR_IN_MS, ERROR_INVALID_END_TIME);
    assert!(hard_cap / 2 >= soft_cap, ERROR_INVALID_SOFT_CAP);
    assert!(max_amount_per_user > min_amount_per_user, ERROR_INVALID_MAX_AMOUNT_PER_USER);

    let sender = tx_context::sender(ctx);
    assert!(!object_bag::contains(&storage.sales, sender), ERROR_ACCOUNT_ALREADY_CREATED_PRESALE);

    let id = object::new(ctx);

    emit(PresaleCreated<T> {
      id: object::uid_to_inner(&id),
      owner: sender,
      start_time,
      hard_cap
    });

    object_bag::add(&mut storage.sales, sender, Presale {
      id,
      balance: balance::zero<T>(),
      soft_cap,
      hard_cap,
      min_amount_per_user,
      max_amount_per_user,
      start_time,
      end_time,
      first_release_percent,
      cycle_length,
      last_cycle_timestamp,
      cycle_release_percent,
      owner: sender,
      root,
      buyers: vec_map::empty(),
      first_claim: false,
      total_raised_amount: 0
    });
  }

  public fun owner_withdraw<T>(storage: &mut Storage, clock_object: &Clock, ctx: &mut TxContext): Coin<T> {
    let sender = tx_context::sender(ctx);
    let presale = borrow_mut_presale<T>(storage, sender);

    let current_timestamp = clock::timestamp_ms(clock_object);
    let current_balance = balance::value(&presale.balance);
    let total_raised_amount = presale.total_raised_amount;
    
    assert!(current_timestamp > presale.end_time, ERROR_HAS_NOT_ENDED);
    assert!(total_raised_amount >= presale.soft_cap, ERROR_PRESALE_FAILED);

    if (!presale.first_claim) {
      presale.first_claim = true;
      presale.last_cycle_timestamp = current_timestamp;

      let withdraw_amout = d_fmul(total_raised_amount, presale.first_release_percent);
      coin::take(&mut presale.balance, (withdraw_amout as u64), ctx)
    } else {
      let timestamp_delta = current_timestamp - presale.last_cycle_timestamp;
      if (presale.cycle_length > timestamp_delta) {
        coin::zero<T>(ctx)
      } else {
        let cycle_withdraw_amount = d_fmul(total_raised_amount, presale.cycle_release_percent);
        let num_of_cycles = timestamp_delta / presale.cycle_length;

        let withdraw_amout = (cycle_withdraw_amount * (num_of_cycles as u256) as u64);
        let safe_withdraw_amount = if (withdraw_amout > current_balance) { current_balance } else { withdraw_amout };

        coin::take(&mut presale.balance, safe_withdraw_amount, ctx)
      }
    }
  } 

  entry fun withdraw_fee(storage: &mut Storage, ctx: &mut TxContext) {
    let value = balance::value(&storage.fee_balance);
    let recipient = storage.treasury;
    transfer::public_transfer(coin::take(&mut storage.fee_balance, value, ctx), recipient);
  }

  entry public fun buy_presale<T>(
    storage: &mut Storage,     
    clock_object: &Clock,
    key: address,
    proof: vector<vector<u8>>,  
    token: Coin<T>, 
    ctx: &mut TxContext) {
      let current_timestamp = clock::timestamp_ms(clock_object);
      let presale = borrow_mut_presale<T>(storage, key);

      let max_amount_per_user = presale.max_amount_per_user;
      let min_amount_per_user = presale.min_amount_per_user;

      assert!(current_timestamp >= presale.start_time, ERROR_HAS_NOT_STARTED);
      assert!(presale.end_time > current_timestamp, ERROR_HAS_ENDED);

      let sender = tx_context::sender(ctx);

      let leaf = hash::sha3_256(bcs::to_bytes(&sender));
    
      assert!(merkle_proof::verify(&proof, presale.root, leaf), ERROR_NOT_WHITELISTED);

      let token_value = coin::value(&token);
      assert!(token_value >= min_amount_per_user, ERROR_INVALID_BUY_AMOUNT);

      let amount = borrow_mut_buyer(presale, sender);

      amount.value = amount.value + token_value;
      assert!(max_amount_per_user >= amount.value, ERROR_MAX_BUY_REACHED);
      
      presale.total_raised_amount = presale.total_raised_amount + token_value;
      assert!(presale.hard_cap >= presale.total_raised_amount, ERROR_HARD_CAP_REACHED);

      balance::join(&mut presale.balance, coin::into_balance(token));

      emit(
        BuyPresale<T> {
          id: object::uid_to_inner(&presale.id),
          buyer: sender,
          amount: token_value
        }
      );
  }

  fun borrow_mut_presale<T>(storage: &mut Storage, key: address):&mut Presale<T> {
    object_bag::borrow_mut(&mut storage.sales, key)
  }

  fun borrow_mut_buyer<T>(presale: &mut Presale<T>, user: address): &mut Amount {
   if (!vec_map::contains(&presale.buyers, &user)) {
      vec_map::insert(&mut presale.buyers, user, Amount { value: 0 });
    };

    vec_map::get_mut(&mut presale.buyers, &user)
  }

  // Admin Only

  entry public fun set_fee_value(_: &PresaleAdminCap, storage: &mut Storage, value: u64) {
    storage.fee_amount = value;
    emit(FeeValueUpdated {new_value: value });
  }

  entry public fun set_treasury(_: &PresaleAdminCap, storage: &mut Storage, treasury: address) {
    storage.treasury = treasury;
    emit(TreasuryUpdated { new_treasury: treasury });
  }

  entry public fun transfer_admin(admin_cap: PresaleAdminCap, recipient: address) {
    assert!(recipient != @0x0, ERROR_INVALID_ADMIN);
    transfer::transfer(admin_cap, recipient);
  }
}