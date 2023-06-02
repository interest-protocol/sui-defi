// Taken from https://github.com/Uniswap/v3-core/blob/main/contracts/libraries/TickMath.sol
module clamm::tick_math {

  use i256::i256::{Self, I256};

  const MAXIMUM_TICK: u256 = 887272; 

  const MIN_SQRT_RATIO: u256 = 4295128739;
  const MAX_SQRT_RATIO: u256 = 1461446703485210103287273052203988822378723970342;
  
  const MAX_U256: u256 = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
  
  const MIN_I24: u256 = 8388608;
  const MAX_I24: u256 = 8388607;

  const EQUAL: u8 = 0;

  const LESS_THAN: u8 = 1;

  const GREATER_THAN: u8 = 2;

  const ERROR_INVALID_SQRT_PRICE_Q96: u64 = 0;
  const ERROR_INVALID_TICK: u64 = 1;
  const ERROR_TICK_OUT_OF_BOUNDS: u64 = 2;

  public fun get_sqrt_ratio_at_tick(tick: &I256): u256 {
    let zero = i256::zero();
    let abs_tick = i256::abs(tick);
    
    let pred = i256::compare(&i256::from(MAXIMUM_TICK), &abs_tick);
    assert!(pred == GREATER_THAN || pred == EQUAL, ERROR_INVALID_TICK);

    let r: u256 = if (!(i256::compare(&i256::and(&abs_tick, &i256::from(0x1)), &zero) == EQUAL)) 
                    { 0xfffcb933bd6fad37aa2d162d1a594001 } else { 0x100000000000000000000000000000000 };
    
    if (!(i256::compare(&i256::and(&abs_tick, &i256::from(0x2)), &zero) == EQUAL))
      r = (r * 0xfff97272373d413259a46990580e213a) >> 128; 

    if (!(i256::compare(&i256::and(&abs_tick, &i256::from(0x4)), &zero) == EQUAL))
      r = (r * 0xfff2e50f5f656932ef12357cf3c7fdcc) >> 128; 

    if (!(i256::compare(&i256::and(&abs_tick, &i256::from(0x8)), &zero) == EQUAL))
      r = (r * 0xffe5caca7e10e4e61c3624eaa0941cd0) >> 128;

    if (!(i256::compare(&i256::and(&abs_tick, &i256::from(0x10)), &zero) == EQUAL))
      r = (r * 0xffcb9843d60f6159c9db58835c926644) >> 128; 

    if (!(i256::compare(&i256::and(&abs_tick, &i256::from(0x20)), &zero) == EQUAL))
      r = (r * 0xff973b41fa98c081472e6896dfb254c0) >> 128;         

    if (!(i256::compare(&i256::and(&abs_tick, &i256::from(0x40)), &zero) == EQUAL))
      r = (r * 0xff2ea16466c96a3843ec78b326b52861) >> 128;  

    if (!(i256::compare(&i256::and(&abs_tick, &i256::from(0x80)), &zero) == EQUAL))
      r = (r * 0xfe5dee046a99a2a811c461f1969c3053) >> 128;  

    if (!(i256::compare(&i256::and(&abs_tick, &i256::from(0x100)), &zero) == EQUAL))
      r = (r * 0xfcbe86c7900a88aedcffc83b479aa3a4) >> 128; 

    if (!(i256::compare(&i256::and(&abs_tick, &i256::from(0x200)), &zero) == EQUAL))
      r = (r * 0xf987a7253ac413176f2b074cf7815e54) >> 128; 

    if (!(i256::compare(&i256::and(&abs_tick, &i256::from(0x400)), &zero) == EQUAL))
      r = (r * 0xf3392b0822b70005940c7a398e4b70f3) >> 128;  

    if (!(i256::compare(&i256::and(&abs_tick, &i256::from(0x800)), &zero) == EQUAL))
      r = (r * 0xe7159475a2c29b7443b29c7fa6e889d9) >> 128;     

    if (!(i256::compare(&i256::and(&abs_tick, &i256::from(0x1000)), &zero) == EQUAL))
      r = (r * 0xd097f3bdfd2022b8845ad8f792aa5825) >> 128; 

    if (!(i256::compare(&i256::and(&abs_tick, &i256::from(0x2000)), &zero) == EQUAL))
      r = (r * 0xa9f746462d870fdf8a65dc1f90e061e5) >> 128;     

    if (!(i256::compare(&i256::and(&abs_tick, &i256::from(0x4000)), &zero) == EQUAL))
      r = (r * 0x70d869a156d2a1b890bb3df62baf32f7) >> 128;   

    if (!(i256::compare(&i256::and(&abs_tick, &i256::from(0x8000)), &zero) == EQUAL))
      r = (r * 0x31be135f97d08fd981231505542fcfa6) >> 128;

    if (!(i256::compare(&i256::and(&abs_tick, &i256::from(0x10000)), &zero) == EQUAL))
      r = (r * 0x9aa508b5b7a84e1c677de54f3e99bc9) >> 128; 

    if (!(i256::compare(&i256::and(&abs_tick, &i256::from(0x20000)), &zero) == EQUAL))
      r = (r * 0x5d6af8dedb81196699c329225ee604) >> 128;

    if (!(i256::compare(&i256::and(&abs_tick, &i256::from(0x40000)), &zero) == EQUAL))
      r = (r * 0x2216e584f5fa1ea926041bedfe98) >> 128; 

    if (!(i256::compare(&i256::and(&abs_tick, &i256::from(0x80000)), &zero) == EQUAL))
      r = (r * 0x48a170391f7dc42444e8fa2) >> 128;    

    if (i256::compare(tick, &zero) == GREATER_THAN) r = MAX_U256 / r;

    (r >> 32) + (if (r % (1 << 32) == 0) { 0 } else { 1 }) 
  }


  public fun get_tick_at_sqrt_ratio(sqrt_price_q96: u256): I256 {
    assert!(sqrt_price_q96 >= MIN_SQRT_RATIO && sqrt_price_q96 < MAX_SQRT_RATIO, ERROR_INVALID_SQRT_PRICE_Q96);

    let ratio: u256 = sqrt_price_q96 << 32;
    let r: u256 = ratio; 
    let msb = 0;

    let f = if (r > 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF) { 1 << 7 } else { 0 };
    msb = msb | f;
    r = r >> f;

    f = if (r > 0xFFFFFFFFFFFFFFFF) { 1 << 6 } else { 0 };
    msb = msb | f;
    r = r >> f;

    f = if (r > 0xFFFFFFFF) { 1 << 5 } else { 0 };
    msb = msb | f;
    r = r >> f;

    f = if (r > 0xFFFF) { 1 << 4 } else { 0 };
    msb = msb | f;
    r = r >> f;

    f = if (r > 0xFF) { 1 << 3 } else { 0 };
    msb = msb | f;
    r = r >> f;

    f = if (r > 0xF) { 1 << 2 } else { 0 };
    msb = msb | f;
    r = r >> f;

    f = if (r > 0x3) { 1 << 1 } else { 0 };
    msb = msb | f;
    r = r >> f;

    f = if (r > 0x1) { 1 } else { 0 };
    msb = msb | f;

    r = if (msb >= 128) { ratio >> (msb - 127) } else { ratio << (127 - msb) };

    let log_2 = i256::shl(&i256::sub(&i256::from((msb as u256)), &i256::from(128)), 64);

    r = (r * r) >> 127;
    f = ((r >> 128) as u8);
    log_2 = i256::or(&log_2, &i256::from(((f as u256) << 63)));
    r = r >> f;

    r = (r * r) >> 127;
    f = ((r >> 128) as u8);
    log_2 = i256::or(&log_2, &i256::from(((f as u256) << 62)));
    r = r >> f;

    r = (r * r) >> 127;
    f = ((r >> 128) as u8);
    log_2 = i256::or(&log_2, &i256::from(((f as u256) << 61)));
    r = r >> f;

    r = (r * r) >> 127;
    f = ((r >> 128) as u8);
    log_2 = i256::or(&log_2, &i256::from(((f as u256) << 60)));
    r = r >> f;

    r = (r * r) >> 127;
    f = ((r >> 128) as u8);
    log_2 = i256::or(&log_2, &i256::from(((f as u256) << 59)));
    r = r >> f;

    r = (r * r) >> 127;
    f = ((r >> 128) as u8);
    log_2 = i256::or(&log_2, &i256::from(((f as u256) << 58)));
    r = r >> f;

    r = (r * r) >> 127;
    f = ((r >> 128) as u8);
    log_2 = i256::or(&log_2, &i256::from(((f as u256) << 57)));
    r = r >> f;

    r = (r * r) >> 127;
    f = ((r >> 128) as u8);
    log_2 = i256::or(&log_2, &i256::from(((f as u256) << 56)));
    r = r >> f;

    r = (r * r) >> 127;
    f = ((r >> 128) as u8);
    log_2 = i256::or(&log_2, &i256::from(((f as u256) << 55)));
    r = r >> f;

    r = (r * r) >> 127;
    f = ((r >> 128) as u8);
    log_2 = i256::or(&log_2, &i256::from(((f as u256) << 54)));
    r = r >> f;

    r = (r * r) >> 127;
    f = ((r >> 128) as u8);
    log_2 = i256::or(&log_2, &i256::from(((f as u256) << 53)));
    r = r >> f;

    r = (r * r) >> 127;
    f = ((r >> 128) as u8);
    log_2 = i256::or(&log_2, &i256::from(((f as u256) << 52)));
    r = r >> f;

    r = (r * r) >> 127;
    f = ((r >> 128) as u8);
    log_2 = i256::or(&log_2, &i256::from(((f as u256) << 51)));
    r = r >> f;

    r = (r * r) >> 127;
    f = ((r >> 128) as u8);
    log_2 = i256::or(&log_2, &i256::from(((f as u256) << 50)));

    let log_sqrt10001 = i256::mul(&log_2, &i256::from(255738958999603826347141));

    let tick_low = i256::shr(&i256::sub(&log_sqrt10001, &i256::from(3402992956809132418596140100660247210)), 128);

    let min_compare = i256::compare(&i256::neg_from(MIN_I24), &tick_low);
    assert!(min_compare == EQUAL || min_compare == LESS_THAN, ERROR_TICK_OUT_OF_BOUNDS);

    let tick_high = i256::shr(&i256::add(&log_sqrt10001, &i256::from(291339464771989622907027621153398088495)), 128);
    
    let max_compare = i256::compare(&i256::from(MAX_I24), &tick_high);
    assert!(max_compare == EQUAL || max_compare == GREATER_THAN, ERROR_TICK_OUT_OF_BOUNDS);

   if (i256::compare(&tick_low, &tick_high) == EQUAL) 
    {
      tick_low
    } 
      else
    {
      if (get_sqrt_ratio_at_tick(&tick_high) <= sqrt_price_q96) { tick_high } else { tick_low }
    }
  }
}