#[test_only]
module clamm::test_utils {
  
  use sui::test_scenario::{Self as test, Scenario};

  const Q64: u256 = 0xFFFFFFFFFFFFFFFF;

  public fun scenario(): Scenario { test::begin(@0x1) }

  public fun people():(address, address) { (@0xBEEF, @0x1337)}
  
  public fun liquidity0(amount: u256, pa: u256, pb: u256): u256 {
    let safe_pa = pa >> 32;
    let safe_pb = pb >> 32;

    let (low, high) = if (safe_pa > safe_pb) (safe_pb, safe_pa) else (safe_pa, safe_pb);
    (amount * (low * high) / Q64) / (high - low)
  }

  public fun liquidity1(amount: u256, pa: u256, pb: u256): u256 {
    let safe_pa = pa >> 32;
    let safe_pb = pb >> 32;

    let (low, high) = if (safe_pa > safe_pb) (safe_pb, safe_pa) else (safe_pa, safe_pb);
    (amount * Q64) / (high - low)
  }  

  public fun min(a: u256, b: u256): u256 {
        if (a < b) a else b
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