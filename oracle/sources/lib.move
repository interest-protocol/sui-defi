module oracle::lib {

  use std::type_name;
  use std::ascii::{String};

  const ERROR_ZERO_DIVISION: u64 = 0;


   public fun get_struct_name_string<T>(): String {
      type_name::into_string(type_name::get<T>())
   }

  public fun mul_div(x: u256, y: u256, z: u256): u256 {
    assert!(z != 0, ERROR_ZERO_DIVISION);
    (x * y) / z
  }

    /// @dev Returns the average of two numbers. The result is rounded towards zero.
    public fun average(a: u256, b: u256): u256 {
        // (a + b) / 2 can overflow.
        (a & b) + (a ^ b) / 2
    }
}