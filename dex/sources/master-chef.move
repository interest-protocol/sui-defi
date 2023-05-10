module dex::master_chef {
  use std::ascii::{String};

  use sui::object::{Self, UID, ID};
  use sui::tx_context::{Self, TxContext};
  use sui::clock::{Self, Clock};
  use sui::balance::{Self, Balance};
  use sui::object_bag::{Self, ObjectBag};
  use sui::object_table::{Self, ObjectTable};
  use sui::table::{Self, Table};
  use sui::transfer;
  use sui::coin::{Self, Coin};
  use sui::event;
  use sui::package::{Self, Publisher};
  
  use ipx::ipx::{Self, IPX, IPXStorage};

  use library::utils::{get_coin_info_string};
  use library::math::{fdiv_u256, fmul_u256};

  const START_TIMESTAMP: u64 = 2288541374;
  const IPX_PER_MS: u64 = 0; // 40M IPX per year
  const IPX_POOL_KEY: u64 = 0;

  const ERROR_POOL_ADDED_ALREADY: u64 = 1;
  const ERROR_NOT_ENOUGH_BALANCE: u64 = 2;
  const ERROR_NO_PENDING_REWARDS: u64 = 3;
  const ERROR_NO_ZERO_ALLOCATION_POINTS: u64 = 4;

  // OTW
  struct MASTER_CHEF has drop {}

  struct MasterChefStorage has key {
    id: UID,
    ipx_per_ms: u64,
    total_allocation_points: u64,
    pool_keys: Table<String, PoolKey>,
    pools: ObjectTable<u64, Pool>,
    start_timestamp: u64,
    publisher: Publisher
  }

  struct Pool has key, store {
    id: UID,
    allocation_points: u64,
    last_reward_timestamp: u64,
    accrued_ipx_per_share: u256,
    balance_value: u64,
    pool_key: u64
  }

  struct AccountStorage has key {
    id: UID,
    accounts: ObjectTable<u64, ObjectBag>
  }

  struct Account<phantom T> has key, store {
    id: UID,
    balance: Balance<T>,
    rewards_paid: u256
  }

  struct PoolKey has store {
    key: u64
  }

  struct MasterChefAdmin has key {
    id: UID
  }

  // Events

  struct SetAllocationPoints<phantom T> has drop, copy {
    key: u64,
    allocation_points: u64,
  }

  struct AddPool<phantom T> has drop, copy {
    key: u64,
    allocation_points: u64,
  }

  struct Stake<phantom T> has drop, copy {
    sender: address,
    amount: u64,
    pool_key: u64,
    rewards: u64
  }

  struct Unstake<phantom T> has drop, copy {
    sender: address,
    amount: u64,
    pool_key: u64,
    rewards: u64
  }

  struct NewAdmin has drop, copy {
    admin: address
  }

  fun init(witness: MASTER_CHEF, ctx: &mut TxContext) {
      // Set up object_tables for the storage objects 
      let pools = object_table::new<u64, Pool>(ctx);  
      let pool_keys = table::new<String, PoolKey>(ctx);
      let accounts = object_table::new<u64, ObjectBag>(ctx);

      let coin_info_string = get_coin_info_string<IPX>();
      
      // Register the IPX farm in pool_keys
      table::add(
        &mut pool_keys, 
        coin_info_string, 
        PoolKey { 
          key: 0,
          }
        );

      // Register the Account object_bag
      object_table::add(
        &mut accounts,
         0,
        object_bag::new(ctx)
      );

      // Register the IPX farm on pools
      object_table::add(
        &mut pools, 
        0, // Key is the length of the object_bag before a new element is added 
        Pool {
          id: object::new(ctx),
          allocation_points: 1000,
          last_reward_timestamp: START_TIMESTAMP,
          accrued_ipx_per_share: 0,
          balance_value: 0,
          pool_key: 0
          }
      );

        // Emit
        event::emit(
          AddPool<IPX> {
          key: 0,
          allocation_points: 1000
          }
        );

      // Share MasterChefStorage
      transfer::share_object(
        MasterChefStorage {
          id: object::new(ctx),
          pools,
          ipx_per_ms: IPX_PER_MS,
          total_allocation_points: 1000,
          pool_keys,
          start_timestamp: START_TIMESTAMP,
          publisher: package::claim(witness, ctx)
        }
      );

      // Share the Account Storage
      transfer::share_object(
        AccountStorage {
          id: object::new(ctx),
          accounts
        }
      );

      // Give the admin_cap to the deployer
      transfer::transfer(MasterChefAdmin { id: object::new(ctx) }, tx_context::sender(ctx));
  }

/**
* @notice It returns the number of Coin<IPX> rewards an account is entitled to for T Pool
* @param storage The IPXStorage shared object
* @param accounts_storage The AccountStorage shared objetct
* @param account The function will return the rewards for this address
* @return rewards
*/
 public fun get_pending_rewards<T>(
  storage: &MasterChefStorage,
  account_storage: &AccountStorage,
  clock_oject: &Clock,
  account: address
  ): u256 {
    
    // If the user never deposited in T Pool, return 0
    if ((!object_bag::contains<address>(object_table::borrow(&account_storage.accounts, get_pool_key<T>(storage)), account))) return 0;

    // Borrow the pool
    let pool = borrow_pool<T>(storage);
    // Borrow the user account for T pool
    let account = borrow_account<T>(storage, account_storage, account);

    // Get the value of the total number of coins deposited in the pool
    let total_balance = (pool.balance_value as u256);
    // Get the value of the number of coins deposited by the account
    let account_balance_value = (balance::value(&account.balance) as u256);

    // If the pool is empty or the user has no tokens in this pool return 0
    if (account_balance_value == 0 || total_balance == 0) return 0;

    // Save the current epoch in memory
    let current_timestamp = clock::timestamp_ms(clock_oject);
    // save the accrued ipx per share in memory
    let accrued_ipx_per_share = pool.accrued_ipx_per_share;

    let is_ipx = pool.pool_key == IPX_POOL_KEY;

    // If the pool is not up to date, we need to increase the accrued_ipx_per_share
    if (current_timestamp > pool.last_reward_timestamp) {
      // Calculate how many epochs have passed since the last update
      let timestamp_delta = ((current_timestamp - pool.last_reward_timestamp) as u256);
      // Calculate the total rewards for this pool
      let rewards = (timestamp_delta * (storage.ipx_per_ms as u256)) * (pool.allocation_points as u256) / (storage.total_allocation_points as u256);

      // Update the accrued_ipx_per_share
      accrued_ipx_per_share = accrued_ipx_per_share + if (is_ipx) {
        fdiv_u256(rewards, (pool.balance_value as u256))
          } else {
          (rewards / (pool.balance_value as u256))
          };
    };
    // Calculate the rewards for the user
    return if (is_ipx) {
      fmul_u256(account_balance_value, accrued_ipx_per_share) - account.rewards_paid
    } else {
      (account_balance_value * accrued_ipx_per_share) - account.rewards_paid
    } 
  }

/**
* @notice It allows the caller to deposit Coin<T> in T Pool. It returns any pending rewards Coin<IPX>
* @param storage The MasterChefStorage shared object
* @param accounts_storage The AccountStorage shared object
* @param ipx_storage The shared Object of IPX
* @param clock_object The Clock object created at genesis
* @param token The Coin<T>, the caller wishes to deposit
* @return Coin<IPX> pending rewards
*/
 public fun stake<T>(
  storage: &mut MasterChefStorage, 
  accounts_storage: &mut AccountStorage,
  ipx_storage: &mut IPXStorage,
  clock_object: &Clock,
  token: Coin<T>,
  ctx: &mut TxContext
 ): Coin<IPX> {
  // We need to update the pool rewards before any mutation
  update_pool<T>(storage, clock_object);
  // Save the sender in memory
  let sender = tx_context::sender(ctx);
  let key = get_pool_key<T>(storage);

   // Register the sender if it is his first time depositing in this pool 
  if (!object_bag::contains<address>(object_table::borrow(&accounts_storage.accounts, key), sender)) {
    object_bag::add(
      object_table::borrow_mut(&mut accounts_storage.accounts, key),
      sender,
      Account<T> {
        id: object::new(ctx),
        balance: balance::zero<T>(),
        rewards_paid: 0
      }
    );
  };

  // Get the needed info to fetch the sender account and the pool
  let pool = borrow_mut_pool<T>(storage);
  let account = borrow_mut_account<T>(accounts_storage, key, sender);
  let is_ipx = pool.pool_key == IPX_POOL_KEY;

  // Initiate the pending rewards to 0
  let pending_rewards = 0;
  
  // Save in memory the current number of coins the sender has deposited
  let account_balance_value = (balance::value(&account.balance) as u256);

  // If he has deposited tokens, he has earned Coin<IPX>; therefore, we update the pending rewards based on the current balance
  if (account_balance_value > 0) pending_rewards = if (is_ipx) {
    fmul_u256(account_balance_value, pool.accrued_ipx_per_share)
  } else {
    (account_balance_value * pool.accrued_ipx_per_share)
  } - account.rewards_paid;

  // Save in memory how mnay coins the sender wishes to deposit
  let token_value = coin::value(&token);

  // Update the pool balance
  pool.balance_value = pool.balance_value + token_value;
  // Update the Balance<T> on the sender account
  balance::join(&mut account.balance, coin::into_balance(token));
  // Consider all his rewards paid
  account.rewards_paid = if (is_ipx) {
    fmul_u256((balance::value(&account.balance) as u256), pool.accrued_ipx_per_share)
  } else {
    (balance::value(&account.balance) as u256) * pool.accrued_ipx_per_share
  };

  event::emit(
    Stake<T> {
      pool_key: key,
      amount: token_value,
      sender,
      rewards: (pending_rewards as u64)
    }
  );

  // Mint Coin<IPX> rewards for the caller.
  ipx::mint(ipx_storage, &storage.publisher, (pending_rewards as u64), ctx)
 }

/**
* @notice It allows the caller to withdraw Coin<T> from T Pool. It returns any pending rewards Coin<IPX>
* @param storage The MasterChefStorage shared object
* @param accounts_storage The AccountStorage shared objetct
* @param ipx_storage The shared Object of IPX
* @param clock_object The Clock object created at genesis
* @param coin_value The value of the Coin<T>, the caller wishes to withdraw
* @return (Coin<IPX> pending rewards, Coin<T>)
*/
 public fun unstake<T>(
  storage: &mut MasterChefStorage, 
  accounts_storage: &mut AccountStorage,
  ipx_storage: &mut IPXStorage,
  clock_object: &Clock,
  coin_value: u64,
  ctx: &mut TxContext
 ): (Coin<IPX>, Coin<T>) {
  // Need to update the rewards of the pool before any  mutation
  update_pool<T>(storage, clock_object);
  
  // Get muobject_table struct of the Pool and Account
  let key = get_pool_key<T>(storage);
  let pool = borrow_mut_pool<T>(storage);
  let account = borrow_mut_account<T>(accounts_storage, key, tx_context::sender(ctx));
  let is_ipx = pool.pool_key == IPX_POOL_KEY;

  // Save the account balance value in memory
  let account_balance_value = balance::value(&account.balance);

  // The user must have enough balance value
  assert!(account_balance_value >= coin_value, ERROR_NOT_ENOUGH_BALANCE);

  // Calculate how many rewards the caller is entitled to
  let pending_rewards = if (is_ipx) {
    fmul_u256((account_balance_value as u256), pool.accrued_ipx_per_share)
  } else {
    ((account_balance_value as u256) * pool.accrued_ipx_per_share)
  } - account.rewards_paid;

  // Withdraw the Coin<T> from the Account
  let staked_coin = coin::take(&mut account.balance, coin_value, ctx);

  // Reduce the balance value in the pool
  pool.balance_value = pool.balance_value - coin_value;
  // Consider all pending rewards paid
  account.rewards_paid = if (is_ipx) {
    fmul_u256((balance::value(&account.balance) as u256), pool.accrued_ipx_per_share)
  } else {
    (balance::value(&account.balance) as u256) * pool.accrued_ipx_per_share
  };

  event::emit(
    Unstake<T> {
      pool_key: key,
      amount: coin_value,
      sender: tx_context::sender(ctx),
      rewards: (pending_rewards as u64)
    }
  );

  // Mint Coin<IPX> rewards and returns the Coin<T>
  (
    ipx::mint(ipx_storage, &storage.publisher, (pending_rewards as u64), ctx),
    staked_coin
  )
 } 

 /**
 * @notice It allows a caller to get all his pending rewards from T Pool
 * @param storage The MasterChefStorage shared object
 * @param accounts_storage The AccountStorage shared objetct
 * @param ipx_storage The shared Object of IPX
 * @param clock_object The Clock object created at genesis
 * @return Coin<IPX> the pending rewards
 */
 public fun get_rewards<T>(
  storage: &mut MasterChefStorage, 
  accounts_storage: &mut AccountStorage,
  ipx_storage: &mut IPXStorage,
  clock_object: &Clock,
  ctx: &mut TxContext
 ): Coin<IPX> {
  // Update the pool before any mutation
  update_pool<T>(storage, clock_object);
  
  // Get muobject_table Pool and Account structs
  let key = get_pool_key<T>(storage);
  let pool = borrow_pool<T>(storage);
  let account = borrow_mut_account<T>(accounts_storage, key, tx_context::sender(ctx));
  let is_ipx = pool.pool_key == IPX_POOL_KEY;

  // Save the user balance value in memory
  let account_balance_value = (balance::value(&account.balance) as u256);

  // Calculate how many rewards the caller is entitled to
  let pending_rewards = if (is_ipx) {
    fmul_u256((account_balance_value as u256), pool.accrued_ipx_per_share)
  } else {
    ((account_balance_value as u256) * pool.accrued_ipx_per_share)
  } - account.rewards_paid;

  // No point to keep going if there are no rewards
  assert!(pending_rewards != 0, ERROR_NO_PENDING_REWARDS);
  
  // Consider all pending rewards paid
  account.rewards_paid = if (is_ipx) {
    fmul_u256((balance::value(&account.balance) as u256), pool.accrued_ipx_per_share)
  } else {
    (balance::value(&account.balance) as u256) * pool.accrued_ipx_per_share
  };

  // Mint Coin<IPX> rewards to the caller
  ipx::mint(ipx_storage, &storage.publisher, (pending_rewards as u64), ctx)
 }

 /**
 * @notice Updates the reward info of all pools registered in this contract
 * @param storage The MasterChefStorage shared object
 */
 public fun update_all_pools(storage: &mut MasterChefStorage, clock_object: &Clock) {
  // Find out how many pools are in the contract
  let length = object_table::length(&storage.pools);

  // Index to keep track of how many pools we have updated
  let index = 0;

  // Save in memory key information before mutating the storage struct
  let ipx_per_ms = storage.ipx_per_ms;
  let total_allocation_points = storage.total_allocation_points;
  let start_timestamp = storage.start_timestamp;

  // Loop to iterate through all pools
  while (index < length) {
    // Borrow muobject_table Pool Struct
    let pool = object_table::borrow_mut(&mut storage.pools, index);

    // Update the pool
    update_pool_internal(pool, clock_object, ipx_per_ms, total_allocation_points, start_timestamp);

    // Increment the index
    index = index + 1;
  }
 }  

 /**
 * @notice Updates the reward info for T Pool
 * @param storage The MasterChefStorage shared object
 */
 public fun update_pool<T>(storage: &mut MasterChefStorage, clock_object: &Clock) {
  // Save in memory key information before mutating the storage struct
  let ipx_per_ms = storage.ipx_per_ms;
  let total_allocation_points = storage.total_allocation_points;
  let start_timestamp = storage.start_timestamp;

  // Borrow muobject_table Pool Struct
  let pool = borrow_mut_pool<T>(storage);

  // Update the pool
  update_pool_internal(
    pool, 
    clock_object,
    ipx_per_ms, 
    total_allocation_points, 
    start_timestamp
  );
 }

 /**
 * @dev The implementation of update_pool
 * @param pool T Pool Struct
 * @param ipx_per_ms Value of Coin<IPX> this module mints per millisecond
 * @param total_allocation_points The sum of all pool points
 * @param start_timestamp The timestamp that this module is allowed to start minting Coin<IPX>
 */
 fun update_pool_internal(
  pool: &mut Pool, 
  clock_object: &Clock,
  ipx_per_ms: u64, 
  total_allocation_points: u64,
  start_timestamp: u64
  ) {
  // Save the current epoch in memory  
  let current_timestamp = clock::timestamp_ms(clock_object);

  // If the pool reward info is up to date or it is not allowed to start minting return;
  if (current_timestamp == pool.last_reward_timestamp || start_timestamp > current_timestamp) return;

  // Save how many epochs have passed since the last update
  let timestamp_delta = current_timestamp - pool.last_reward_timestamp;

  // Update the current pool last reward timestamp
  pool.last_reward_timestamp = current_timestamp;

  // There is nothing to do if the pool is not allowed to mint Coin<IPX> or if there are no coins deposited on it.
  if (pool.allocation_points == 0 || pool.balance_value == 0) return;

  // Calculate the rewards (pool_allocation * milliseconds * ipx_per_epoch) / total_allocation_points
  let rewards = ((pool.allocation_points as u256) * (timestamp_delta as u256) * (ipx_per_ms as u256) / (total_allocation_points as u256));

  // Update the accrued_ipx_per_share
  pool.accrued_ipx_per_share = pool.accrued_ipx_per_share + if (pool.pool_key == IPX_POOL_KEY) {
    fdiv_u256(rewards, (pool.balance_value as u256))
  } else {
    (rewards / (pool.balance_value as u256))
  };
 }

 /**
 * @dev The updates the allocation points of the IPX Pool and the total allocation points
 * The IPX Pool must have 1/3 of all other pools allocations
 * @param storage The MasterChefStorage shared object
 */
 fun update_ipx_pool(storage: &mut MasterChefStorage) {
    // Save the total allocation points in memory
    let total_allocation_points = storage.total_allocation_points;

    // Borrow the IPX muobject_table pool struct
    let pool = borrow_mut_pool<IPX>(storage);

    // Get points of all other pools
    let all_other_pools_points = total_allocation_points - pool.allocation_points;

    // Divide by 3 to get the new ipx pool allocation
    let new_ipx_pool_allocation_points = all_other_pools_points / 3;

    // Calculate the total allocation points
    let total_allocation_points = total_allocation_points + new_ipx_pool_allocation_points - pool.allocation_points;

    // Update pool and storage
    pool.allocation_points = new_ipx_pool_allocation_points;
    storage.total_allocation_points = total_allocation_points;
 } 

  /**
  * @dev Finds T Pool from MasterChefStorage
  * @param storage The IPXStorage shared object
  * @return muobject_table T Pool
  */
 fun borrow_mut_pool<T>(storage: &mut MasterChefStorage): &mut Pool {
  let key = get_pool_key<T>(storage);
  object_table::borrow_mut(&mut storage.pools, key)
 }

/**
* @dev Finds T Pool from MasterChefStorage
* @param storage The IPXStorage shared object
* @return immuobject_table T Pool
*/
public fun borrow_pool<T>(storage: &MasterChefStorage): &Pool {
  let key = get_pool_key<T>(storage);
  object_table::borrow(&storage.pools, key)
 }

/**
* @dev Finds the key of a pool
* @param storage The MasterChefStorage shared object
* @return the key of T Pool
*/
 fun get_pool_key<T>(storage: &MasterChefStorage): u64 {
    table::borrow<String, PoolKey>(&storage.pool_keys, get_coin_info_string<T>()).key
 }

/**
* @dev Finds an Account struct for T Pool
* @param storage The MasterChefStorage shared object
* @param accounts_storage The AccountStorage shared object
* @param sender The address of the account we wish to find
* @return immuobject_table AccountStruct of sender for T Pool
*/ 
 public fun borrow_account<T>(storage: &MasterChefStorage, accounts_storage: &AccountStorage, sender: address): &Account<T> {
  object_bag::borrow(object_table::borrow(&accounts_storage.accounts, get_pool_key<T>(storage)), sender)
 }

/**
* @dev Finds an Account struct for T Pool
* @param storage The MasterChefStorage shared object
* @param accounts_storage The AccountStorage shared object
* @param sender The address of the account we wish to find
* @return immuobject_table AccountStruct of sender for T Pool
*/ 
 public fun account_exists<T>(storage: &MasterChefStorage, accounts_storage: &AccountStorage, sender: address): bool {
  object_bag::contains(object_table::borrow(&accounts_storage.accounts, get_pool_key<T>(storage)), sender)
 }

/**
* @dev Finds an Account struct for T Pool
* @param accounts_storage The AccountStorage shared object
* @param sender The address of the account we wish to find
* @return muobject_table AccountStruct of sender for T Pool
*/ 
fun borrow_mut_account<T>(accounts_storage: &mut AccountStorage, key: u64, sender: address): &mut Account<T> {
  object_bag::borrow_mut(object_table::borrow_mut(&mut accounts_storage.accounts, key), sender)
 }

/**
* @dev Updates the value of Coin<IPX> this module is allowed to mint per millisecond
* @param _ the admin cap
* @param storage The MasterChefStorage shared object
* @param ipx_per_ms the new ipx_per_ms
* Requirements: 
* - The caller must be the admin
*/ 
 entry public fun update_ipx_per_ms(
  _: &MasterChefAdmin,
  storage: &mut MasterChefStorage,
  clock_object: &Clock,
  ipx_per_ms: u64
  ) {
    // Update all pools rewards info before updating the ipx_per_epoch
    update_all_pools(storage, clock_object);
    storage.ipx_per_ms = ipx_per_ms;
 }

/**
* @dev Register a Pool for Coin<T> in this module
* @param _ the admin cap
* @param storage The MasterChefStorage shared object
* @param accounts_storage The AccountStorage shared object
* @param allocaion_points The allocation points of the new T Pool
* @param update if true we will update all pools rewards before any update
* Requirements: 
* - The caller must be the admin
* - Only one Pool per Coin<T>
*/ 
 entry public fun add_pool<T>(
  _: &MasterChefAdmin,
  storage: &mut MasterChefStorage,
  accounts_storage: &mut AccountStorage,
  clock_object: &Clock,
  allocation_points: u64,
  update: bool,
  ctx: &mut TxContext
 ) {
  // Ensure that a new pool has an allocation
  assert!(allocation_points != 0, ERROR_NO_ZERO_ALLOCATION_POINTS);
  // Save total allocation points and start epoch in memory
  let total_allocation_points = storage.total_allocation_points;
  let start_timestamp = storage.start_timestamp;
  // Update all pools if true
  if (update) update_all_pools(storage, clock_object);

  let coin_info_string = get_coin_info_string<T>();

  // Make sure Coin<T> has never been registered
  assert!(!table::contains(&storage.pool_keys, coin_info_string), ERROR_POOL_ADDED_ALREADY);

  // Update the total allocation points
  storage.total_allocation_points = total_allocation_points + allocation_points;

  // Current number of pools is the key of the new pool
  let key = table::length(&storage.pool_keys);

  // Register the Account object_bag
  object_table::add(
    &mut accounts_storage.accounts,
    key,
    object_bag::new(ctx)
  );

  // Register the PoolKey
  table::add(
    &mut storage.pool_keys,
    coin_info_string,
    PoolKey {
      key
    }
  );

  // Save the current_epoch in memory
  let current_timestamp = clock::timestamp_ms(clock_object);

  // Register the Pool in IPXStorage
  object_table::add(
    &mut storage.pools,
    key,
    Pool {
      id: object::new(ctx),
      allocation_points,
      last_reward_timestamp: if (current_timestamp > start_timestamp) { current_timestamp } else { start_timestamp },
      accrued_ipx_per_share: 0,
      balance_value: 0,
      pool_key: key
    }
  );

  // Emit
  event::emit(
    AddPool<T> {
      key,
      allocation_points
    }
  );

  // Update the IPX Pool allocation
  update_ipx_pool(storage);
 }

/**
* @dev Updates the allocation points for T Pool
* @param _ the admin cap
* @param storage The MasterChefStorage shared object
* @param allocation_points The new allocation points for T Pool
* @param update if true we will update all pools rewards before any update
* Requirements: 
* - The caller must be the admin
* - The Pool must exist
*/ 
 entry public fun set_allocation_points<T>(
  _: &MasterChefAdmin,
  storage: &mut MasterChefStorage,
  clock_object: &Clock,
  allocation_points: u64,
  update: bool
 ) {
  // Save the total allocation points in memory
  let total_allocation_points = storage.total_allocation_points;
  // Update all pools
  if (update) update_all_pools(storage, clock_object);

  // Get Pool key and Pool muobject_table Struct
  let key = get_pool_key<T>(storage);
  let pool = borrow_mut_pool<T>(storage);

  // No point to update if the new allocation_points is not different
  if (pool.allocation_points == allocation_points) return;

  // Update the total allocation points
  let total_allocation_points = total_allocation_points + allocation_points - pool.allocation_points;

  // Update the T Pool allocation points
  pool.allocation_points = allocation_points;
  // Update the total allocation points
  storage.total_allocation_points = total_allocation_points;

  event::emit(
    SetAllocationPoints<T> {
      key,
      allocation_points
    }
  );

  // Update the IPX Pool allocation points
  update_ipx_pool(storage);
 }
 
 /**
 * @notice It allows the admin to transfer the AdminCap to a new address
 * @param admin The IPXAdmin Struct
 * @param recipient The address of the new admin
 */
 entry public fun transfer_admin(
  admin: MasterChefAdmin,
  recipient: address
 ) {
  transfer::transfer(admin, recipient);
  event::emit(NewAdmin { admin: recipient })
 }

 /**
 * @notice A getter function
 * @param storage The MasterChefStorage shared object
 * @param accounts_storage The AccountStorage shared object
 * @param sender The address we wish to check
 * @return balance of the account on T Pool and rewards paid 
 */
 public fun get_account_info<T>(storage: &MasterChefStorage, accounts_storage: &AccountStorage, sender: address): (u64, u256) {
    let account = object_bag::borrow<address, Account<T>>(object_table::borrow(&accounts_storage.accounts, get_pool_key<T>(storage)), sender);
    (
      balance::value(&account.balance),
      account.rewards_paid
    )
  }

/**
 * @notice A getter function
 * @param storage The MasterChefStorage shared object
 * @return allocation_points, last_reward_timestamp, accrued_ipx_per_share, balance_value of T Pool
 */
  public fun get_pool_info<T>(storage: &MasterChefStorage): (u64, u64, u256, u64) {
    let key = get_pool_key<T>(storage);
    let pool = object_table::borrow(&storage.pools, key);
    (
      pool.allocation_points,
      pool.last_reward_timestamp,
      pool.accrued_ipx_per_share,
      pool.balance_value
    )
  }

  /**
 * @notice A getter function
 * @param storage The MasterChefStorage shared object
 * @return total ipx_per_ms, total_allocation_points, start_timestamp
 */
  public fun get_master_chef_storage_info(storage: &MasterChefStorage): (u64, u64, u64) {
    (
      storage.ipx_per_ms,
      storage.total_allocation_points,
      storage.start_timestamp
    )
  }
  
  #[test_only]
  public fun init_for_testing(ctx: &mut TxContext) {
    init(MASTER_CHEF {} ,ctx);
  }

  #[test_only]
  public fun get_publisher_id(storage: &MasterChefStorage): ID {
    object::id(&storage.publisher)
  }
}
