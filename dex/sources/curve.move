// It contains the two AMM constant invariants of Interest Protocol
// Volatile => k = y * x 
// Stable => k = x^3y + xy^3
module dex::curve {

  use library::utils::{are_types_equal};

  struct Stable {}

  struct Volatile {}

  /**
  * @dev It allows the caller to know if the type is a supported curve
  * @return true if the type {T} is either {Volatile} or {Stable}
  */
  public fun is_curve<T>(): bool {
    are_types_equal<Volatile, T>() || are_types_equal<Stable, T>()
  }

  /**
  * @dev It helps to caller to know if {T} is {Volatile}
  * @return true if it is {Volatile}
  */
  public fun is_volatile<T>(): bool {
    are_types_equal<Volatile, T>()
  }
}