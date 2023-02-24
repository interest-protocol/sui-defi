module interest_protocol::math {

  const SCALAR: u256 = 1000000000;

  public fun fmul(x: u64, y: u64): u64 {
    ((((x as u256) * (y as u256) ) / SCALAR) as u64)
  }

  public fun fmul_u256(x: u256, y: u256): u256 {
    ((x * y ) / SCALAR)
  }

  public fun fdiv(x: u64, y: u64): u64 {
    ((((x as u256) * SCALAR ) / (y as u256)) as u64)
  }

  public fun mul_div_u128(x: u128, y: u128, z: u128): u128 {
    ((x as u256) * (y as u256) / (z as u256) as u128)
  }

  public fun one(): u256 {
    SCALAR
  }
}