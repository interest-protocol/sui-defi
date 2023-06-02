#[test_only]
module clamm::test_utils {
  
  use sui::test_scenario::{Self as test, Scenario};

  const Q96: u256 = 0x1000000000000000000000000;
  const Q128: u256 = 0x100000000000000000000000000000000;
  const Q96_RESOLUTION: u8 =96;

  public fun scenario(): Scenario { test::begin(@0x1) }

  public fun people():(address, address) { (@0xBEEF, @0x1337)}

  public fun create_sqrt_price(value: u256): u256 {
    sqrt(value << Q96_RESOLUTION)
  }

  /// @dev Returns a to the power of b.
  /// Return the value of a base raised to a power
  public fun pow(base: u256, exponent: u8): u256 {
        let res = 1;
        while (exponent >= 1) {
            if (exponent % 2 == 0) {
                base = base * base;
                exponent = exponent / 2;
            } else {
                res = res * base;
                exponent = exponent - 1;
            }
        };

        res
    }

    public fun sqrt(y: u256): u256 {
        let z = 0;
        if (y > 3) {
            z = y;
            let x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        };
        z
  }
}