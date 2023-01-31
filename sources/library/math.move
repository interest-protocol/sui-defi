module whirpool::math {

  const SCALAR: u256 = 1000000000;

  public fun fmul(x: u64, y: u64): u64 {
    ((((x as u256) * (y as u256) ) / SCALAR) as u64)
  }

  public fun fdiv(x: u64, y: u64): u64 {
    ((((x as u256) * SCALAR ) / (y as u256)) as u64)
  }

  public fun one(): u64 {
    (SCALAR as u64)
  }
}