#[test_only]
module library::foo {

  use sui::object::{Self, UID, ID};
  use sui::package::{Self, Publisher};
  use sui::transfer;
  use sui::tx_context::{TxContext};

  struct FOO has drop {}

  struct FooStorage has key {
    id: UID,
    publisher: Publisher
  }

  fun init(witness: FOO, ctx: &mut TxContext) {

    transfer::share_object(
      FooStorage {
        id: object::new(ctx),
        publisher: package::claim<FOO>(witness, ctx)
      }
    );
  }

  public fun get_publisher(storage: &FooStorage): &Publisher {
    &storage.publisher
  }

  public fun get_publisher_id(storage: &FooStorage): ID {
    object::id(&storage.publisher)
  }

 #[test_only]
  public fun init_for_testing(ctx: &mut TxContext) {
    init(FOO {}, ctx);
  }
}