module private_sale::core {
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
  const ERROR_PRESALE_SUCCESSED: u64 = 15;
  const ERROR_NO_BALANCE: u64 = 16;

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
    start_time: u64, // milliseconds
    end_time: u64, // milliseconds
    first_release_amount: u64, // scaled to 1e18
    cycle_length: u64, // milliseconds
    last_cycle_timestamp: u64, // milliseconds
    cycle_release_amount: u64, // scaled to 1e18
    owner: address,
    root: vector<u8>,
    buyers: VecMap<address, Amount>,
    first_claim_done: bool,
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

  struct NewAdmin has copy, drop {
    new_admin: address
  }

  struct OwnerWithdraw<phantom T> has copy, drop {
    id: ID,
    owner: address,
    amount: u64
  }

  struct WithdrawFee has drop, copy {
    treasury: address, 
    amount: u64
  }

  struct RedeemCoin<phantom T> has drop, copy {
    id: ID,
    user: address,
    amount: u64
  }

  fun init(ctx: &mut TxContext) {
    
    // Share the Storage Object
    transfer::share_object(
      Storage {
        id: object::new(ctx),
        sales: object_bag::new(ctx),
        fee_balance: balance::zero<SUI>(), // stores all fees paid
        fee_amount: 10000000000, // 10 SUI
        treasury: @treasury
      }
    );

    // Give Admin rights to the deployer 
    transfer::transfer(PresaleAdminCap { id: object::new(ctx) }, tx_context::sender(ctx));
  }

  /**
  * @notice It allows the sender to create a presale. The module only allows one pre-sale per address.
  * @param storage The shared Storage object
  * @param The shared Clock object
  * @param fee The fee to pay the treasury for creating a pre sale
  * @param soft_cap The minimum value of Coin<T>, this presale has to raise
  * @param hard_cap The maximum value of Coin<T>, this presale can raise
  * @param min_amount_per_user The minimum value of Coin<T> a user can buy
  * @param max_amount_per_user The maximum value of Coin<T> a user can buy
  * @param start_time The on chain timestamp in which users are allowed to buy
  * @param end_time Users must buy before this timestamp
  * @param first_release_amount The % of tokens the owner will receive as soon as the private sale ends
  * @param cycle_length The time the owner has to wait since his last withdraw in milliseconds
  * @param last_cycle_timestamp The time stamp of the last owner withdraw
  * @param cycle_release_amount The % of tokens to release each cycle after the first release
  * @param root The root of the merkle tree of whitelisted accounts
  */
  public fun create_presale<T>(
    storage: &mut Storage,
    clock_object: &Clock,
    fee: Coin<SUI>,
    soft_cap: u64,
    hard_cap: u64,
    min_amount_per_user: u64,
    max_amount_per_user: u64,
    start_time: u64,
    end_time: u64,
    first_release_amount: u64,
    cycle_length: u64,
    last_cycle_timestamp: u64,
    cycle_release_amount: u64,
    root: vector<u8>,
    ctx: &mut TxContext
  ) {
    // User must pay the fee
    assert!(coin::value(&fee)>= storage.fee_amount, ERROR_INVALID_FEE);
    // Store the fee to be redeemed later
    balance::join(&mut storage.fee_balance, coin::into_balance(fee));

    // The start time has to be at least one hour ahead of the current time
    assert!(start_time >= clock::timestamp_ms(clock_object) + ONE_HOUR_IN_MS, ERROR_INVALID_START_TIME);

    // The end time must be at least one hour ahead of the start time
    assert!(end_time >= start_time + ONE_HOUR_IN_MS, ERROR_INVALID_END_TIME);

    // The soft cap must be at least half of the hard cap
    assert!(soft_cap * 2 >= hard_cap, ERROR_INVALID_SOFT_CAP);

    // The max per user must be higher than the min per user
    assert!(max_amount_per_user > min_amount_per_user, ERROR_INVALID_MAX_AMOUNT_PER_USER);

    // The address of the sender (owner of the presale) is the key of the object so there is one Presale per address
    let sender = tx_context::sender(ctx);
    // Make sure the sender never created a presale before
    assert!(!object_bag::contains(&storage.sales, sender), ERROR_ACCOUNT_ALREADY_CREATED_PRESALE);

    // Create a UID
    let id = object::new(ctx);

    // Emit event
    emit(PresaleCreated<T> {
      id: object::uid_to_inner(&id),
      owner: sender,
      start_time,
      hard_cap
    });

    // Add the Presale to storage
    object_bag::add(&mut storage.sales, sender, Presale {
      id,
      balance: balance::zero<T>(),
      soft_cap,
      hard_cap,
      min_amount_per_user,
      max_amount_per_user,
      start_time,
      end_time,
      first_release_amount,
      cycle_length,
      last_cycle_timestamp,
      cycle_release_amount,
      owner: sender,
      root,
      buyers: vec_map::empty(),
      first_claim_done: false,
      total_raised_amount: 0
    });
  }

  /**
  * @notice It allows the creator of the Presale to withdraw the raised Coin<T>
  * @param storage The shared Storage object
  * @param clock_object The shared Clock object 
  * @return Coin<T>
  */
  public fun owner_withdraw<T>(storage: &mut Storage, clock_object: &Clock, ctx: &mut TxContext): Coin<T> {
    let sender = tx_context::sender(ctx);
    // This presale belongs to this sender because the owner is the key. 
    let presale = borrow_mut_presale<T>(storage, sender);

    let current_timestamp = clock::timestamp_ms(clock_object);
    let current_balance = balance::value(&presale.balance);
    let total_raised_amount = presale.total_raised_amount;
    
    // The presale must have ended.
    assert!(current_timestamp > presale.end_time, ERROR_HAS_NOT_ENDED);
    // The presale must raise more than the soft cap.
    assert!(total_raised_amount >= presale.soft_cap, ERROR_PRESALE_FAILED);

    // If it is the first claim, we process the first branch
    if (!presale.first_claim_done) {
      // update first_claim_done
      presale.first_claim_done = true;
      // update last_cycle_timestamp
      presale.last_cycle_timestamp = current_timestamp;

      emit(OwnerWithdraw<T> { id: object::uid_to_inner(&presale.id), owner: sender, amount: presale.first_release_amount });

      // Return the coin
      coin::take(&mut presale.balance, presale.first_release_amount, ctx)
    } else {
      // If it is not the first claim we go to the second branch

      // alculate how much time has passed in the last cycle
      let timestamp_delta = current_timestamp - presale.last_cycle_timestamp;
      // If not enough time as passed we return an empty coin
      if (presale.cycle_length > timestamp_delta) {
        coin::zero<T>(ctx)
      } else {
        // If enough time has passed we calculate the reward per cycle

        // We calculate the number of cycles that have passed
        let num_of_cycles = timestamp_delta / presale.cycle_length;

        // Multiply the number of cycles that have passed * number of tokens per cycle
        let withdraw_amount = presale.cycle_release_amount * num_of_cycles;

        // Make sure there are enough tokens to withdraw
        let safe_withdraw_amount = if (withdraw_amount > current_balance) { current_balance } else { withdraw_amount };
        
        emit(OwnerWithdraw<T> { id: object::uid_to_inner(&presale.id), owner: sender, amount: safe_withdraw_amount });
        
        // return them
        coin::take(&mut presale.balance, safe_withdraw_amount, ctx)
      }
    }
  }
  
  /**
  * @notice If a Presale fails, it allows an investor to get back his investment. 
  * @param storage The shared Storage object
  * @param clock_object The shared Clock object 
  * @param key The adddress of the owner of the Presale  
  * @return Coin<T> of the sender
  */
  public fun redeem_coins<T>(storage: &mut Storage, clock_object: &Clock, key: address, ctx: &mut TxContext): Coin<T> {
    let presale = borrow_mut_presale<T>(storage, key);
    let current_timestamp = clock::timestamp_ms(clock_object);

    // The presale must have ended
    assert!(current_timestamp > presale.end_time, ERROR_HAS_NOT_ENDED);
    // If it raised less than the soft cap, it failed
    assert!(presale.total_raised_amount < presale.soft_cap, ERROR_PRESALE_SUCCESSED);

    let sender = tx_context::sender(ctx);
    
    let amount = borrow_mut_buyer(presale, sender);
    // Save the caller investment value locally
    let redeem_amount = amount.value;

    // He must have invested some value
    assert!(redeem_amount != 0, ERROR_NO_BALANCE);
    // consider it redeemed
    amount.value = 0;

    emit(RedeemCoin<T> { id: object::uid_to_inner(&presale.id), user: sender, amount: redeem_amount });

    // return the coins
    coin::take(&mut presale.balance, redeem_amount, ctx)
  }

 public fun buy_presale<T>(
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

  entry fun withdraw_fee(storage: &mut Storage, ctx: &mut TxContext) {
    let amount = balance::value(&storage.fee_balance);
    let treasury = storage.treasury;
    transfer::public_transfer(coin::take(&mut storage.fee_balance, amount, ctx), treasury );
    emit(WithdrawFee { treasury, amount });
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

  entry public fun update_fee_value(_: &PresaleAdminCap, storage: &mut Storage, value: u64) {
    storage.fee_amount = value;
    emit(FeeValueUpdated {new_value: value });
  }

  entry public fun update_treasury(_: &PresaleAdminCap, storage: &mut Storage, treasury: address) {
    storage.treasury = treasury;
    emit(TreasuryUpdated { new_treasury: treasury });
  }

  entry public fun transfer_admin(admin_cap: PresaleAdminCap, recipient: address) {
    assert!(recipient != @0x0, ERROR_INVALID_ADMIN);
    transfer::transfer(admin_cap, recipient);
    emit(NewAdmin { new_admin: recipient });
  }
}