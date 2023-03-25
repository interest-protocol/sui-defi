module interest_protocol::curve {

  use interest_protocol::utils::{are_types_equal};

  struct Stable {}

  struct Volatile {}

  public fun is_curve<T>(): bool {
    are_types_equal<Volatile, T>() || are_types_equal<Stable, T>()
  }

  public fun is_volatile<T>(): bool {
    are_types_equal<Volatile, T>()
  }
}