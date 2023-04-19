module library::math {

  const SCALAR: u256 = 1000000000; // 1e9 - Same as Sui decimals
  const DOUBLE_SCALAR: u256 = 1000000000000000000; // 1e18 - More accuracy

  public fun fmul_u256(x: u256, y: u256): u256 {
    ((x * y ) / SCALAR)
  }

  public fun fdiv_u256(x: u256, y: u256): u256 {
    (x * SCALAR ) / y
  }

  public fun d_fmul(x: u64, y: u64): u256 {
    (((x as u256) * (y as u256) ) / DOUBLE_SCALAR)
  }

  public fun d_fdiv(x: u64, y: u64): u256 {
    (((x as u256) * DOUBLE_SCALAR ) / (y as u256))
  }

  public fun d_fmul_u256(x: u256, y: u256): u256 {
    ((x * y ) / DOUBLE_SCALAR)
  }

  public fun d_fdiv_u256(x: u256, y: u256): u256 {
    (x * DOUBLE_SCALAR ) / y
  }
  
  public fun mul_div_u128(x: u128, y: u128, z: u128): u128 {
    ((x as u256) * (y as u256) / (z as u256) as u128)
  }

  public fun mul_div(x: u64, y: u64, z: u64): u64 {
    (((x as u256) * (y as u256)) / (z as u256) as u64)
  }

  public fun sqrt_u256(y: u256): u256 {
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

  public fun scalar(): u256 {
    SCALAR
  }

  public fun double_scalar(): u256 {
    DOUBLE_SCALAR
  }
}