module clamm::math_u256 {

  const ERROR_ZERO_DIVISION: u64 = 0;
  
  public fun mul_div(x: u256, y: u256, z: u256): u256 {
    assert!(z != 0, ERROR_ZERO_DIVISION);

    (x * y) / z
  }

    //  let base = mul_div_u128((elastic as u128), rebase.base, rebase.elastic); 
    //     if (round_up && (mul_div_u128(base, rebase.elastic, rebase.base) < (elastic as u128))) base = base + 1;

  public fun mul_div_round_up(x: u256, y: u256, z: u256): u256 {
    let result = mul_div(x, y, z);

    if (((x * y) % z) != 0) result = result + 1;

    result 
  }

  public fun div_round_up(a: u256, b: u256): u256 {
        assert!(b != 0, ERROR_ZERO_DIVISION);
        // (a + b - 1) / b can overflow on addition, so we distribute.
        if (a == 0) 0 else (a - 1) / b + 1
  }
}