#[test_only]
module clamm::tick_math_tests {
  use sui::test_utils::{assert_eq};
  
  use clamm::tick_math::{get_sqrt_ratio_at_tick, get_tick_at_sqrt_ratio};
  
  use i256::i256::{one, sub, neg_from, from, add};

  const MAX_TICK: u256 = 887272;
  const MIN_SQRT_RATIO: u256 = 4295128739;
  const MAX_SQRT_RATIO: u256 = 1461446703485210103287273052203988822378723970342;

  const EQUAL: u8 = 0;

  const LESS_THAN: u8 = 1;

  const GREATER_THAN: u8 = 2;

  #[test]
  #[expected_failure(abort_code = clamm::tick_math::ERROR_INVALID_TICK)]
  fun test_error_get_sqrt_ratio_at_tick_too_low() {
    assert_eq(get_sqrt_ratio_at_tick(&sub(&neg_from(MAX_TICK), &one())), 1);
  }

  #[test]
  #[expected_failure(abort_code = clamm::tick_math::ERROR_INVALID_TICK)]
  fun test_error_get_sqrt_ratio_at_tick_too_high() {
    assert_eq(get_sqrt_ratio_at_tick(&add(&from(MAX_TICK), &one())), 1);
  }

  #[test]
  fun test_get_sqrt_ratio_at_tick() {
    assert_eq(get_sqrt_ratio_at_tick(&neg_from(MAX_TICK)), MIN_SQRT_RATIO);
    assert_eq(get_sqrt_ratio_at_tick(&add(&neg_from(MAX_TICK), &one())), 4295343490);
    assert_eq(get_sqrt_ratio_at_tick(&sub(&from(MAX_TICK), &one())), 1461373636630004318706518188784493106690254656249);
    assert_eq(get_sqrt_ratio_at_tick(&from(MAX_TICK)), MAX_SQRT_RATIO);
    assert_eq(get_sqrt_ratio_at_tick(&neg_from(MAX_TICK)), 0x01000276a3);
    assert_eq(get_sqrt_ratio_at_tick(&from(MAX_TICK)), 0xfffd8963efd1fc6a506488495d951d5263988d26);
    assert_eq(get_sqrt_ratio_at_tick(&neg_from(50)), 0xff5c5f6fd987594269220c6a);
    assert_eq(get_sqrt_ratio_at_tick(&from(50)), 0x0100a4096906976f1080c4042d);
    assert_eq(get_sqrt_ratio_at_tick(&neg_from(100)), 0xfeb927758f54316b45a2d3b3);
    assert_eq(get_sqrt_ratio_at_tick(&from(100)), 0x0101487bee1c17ddb45ce0bae0); 
    assert_eq(get_sqrt_ratio_at_tick(&neg_from(250)), 0xfcd1f06e35bcde2b89848a21);
    assert_eq(get_sqrt_ratio_at_tick(&from(250)), 0x0103384cc810558cdf8c440237);
    assert_eq(get_sqrt_ratio_at_tick(&neg_from(500)), 0xf9adfd836f8e67fcd3fbc8f1);
    assert_eq(get_sqrt_ratio_at_tick(&from(500)), 0x01067af7be7f9ba68649faa103);   
    assert_eq(get_sqrt_ratio_at_tick(&neg_from(1000)), 0xf383ed6a4db4dabd35fb4457);
    assert_eq(get_sqrt_ratio_at_tick(&from(1000)), 0x010d1fee2afe8561359d69a466);   
    assert_eq(get_sqrt_ratio_at_tick(&neg_from(2500)), 0xe1ebadaf4348cf03065c78b0);
    assert_eq(get_sqrt_ratio_at_tick(&from(2500)), 0x0122158d8bd5e8608ce87a2a89); 
    assert_eq(get_sqrt_ratio_at_tick(&neg_from(3000)), 0xdc57c7edc0953c8a806afe03);
    assert_eq(get_sqrt_ratio_at_tick(&from(3000)), 0x01296d65dd39b9cdb1686122fd); 
    assert_eq(get_sqrt_ratio_at_tick(&neg_from(4000)), 0xd198e00abfc929b20b3a5e0b);
    assert_eq(get_sqrt_ratio_at_tick(&from(4000)), 0x0138ad0cfe73ce1e71b237794f); 
    assert_eq(get_sqrt_ratio_at_tick(&neg_from(5000)), 0xc760204669e1dc7cd7c087b7);
    assert_eq(get_sqrt_ratio_at_tick(&from(5000)), 0x0148b4d68157d6e8e30d43811e); 
    assert_eq(get_sqrt_ratio_at_tick(&neg_from(150000)), 0x2442b231afa40110811e3d);
    assert_eq(get_sqrt_ratio_at_tick(&from(150000)), 0x070f5d5483c9bc7ecaca01eb4661);  
    assert_eq(get_sqrt_ratio_at_tick(&neg_from(250000)), 0x3e8fdc0fc4060814fc0e);
    assert_eq(get_sqrt_ratio_at_tick(&from(250000)), 0x041789a3a867a82754af6edc398f28); 
    assert_eq(get_sqrt_ratio_at_tick(&neg_from(500000)), 0x0f49ff6f39bb048b);
    assert_eq(get_sqrt_ratio_at_tick(&from(500000)), 0x10be7722ac12c046792462c77d5c3d5366); 
    assert_eq(get_sqrt_ratio_at_tick(&neg_from(738203)), 0x06bd3a9098e3);
    assert_eq(get_sqrt_ratio_at_tick(&from(738203)), 0x25fca1f4cc2b919d309c63cc3bf4a65dae57ad);         
  }

  #[test]
  #[expected_failure(abort_code = clamm::tick_math::ERROR_INVALID_SQRT_PRICE_Q96)]
  fun test_get_tick_at_sqrt_ratio_error_low_price() {
    assert_eq(get_tick_at_sqrt_ratio(MIN_SQRT_RATIO - 1), one());
  }

  #[test]
  #[expected_failure(abort_code = clamm::tick_math::ERROR_INVALID_SQRT_PRICE_Q96)]
  fun test_get_tick_at_sqrt_ratio_error_high_price() {
    assert_eq(get_tick_at_sqrt_ratio(MAX_SQRT_RATIO), one());
  }

  #[test]
  fun test_get_tick_at_sqrt_ratio() {
    assert_eq(get_tick_at_sqrt_ratio(MIN_SQRT_RATIO), neg_from(MAX_TICK));
    assert_eq(get_tick_at_sqrt_ratio(4295343490), add(&neg_from(MAX_TICK), &one()));
    assert_eq(get_tick_at_sqrt_ratio(1461373636630004318706518188784493106690254656249), sub(&from(MAX_TICK), &one()));
    assert_eq(get_tick_at_sqrt_ratio(MAX_SQRT_RATIO - 1), sub(&from(MAX_TICK), &one()));
    {
      let ratio = 4295128739;
      let tick = get_tick_at_sqrt_ratio(ratio);
      let ratio_of_tick = get_sqrt_ratio_at_tick(&tick);
      let ratio_of_tick_plus_one = get_sqrt_ratio_at_tick(&add(&tick, &one()));

      assert_eq(ratio >= ratio_of_tick, true);
      assert_eq(ratio < ratio_of_tick_plus_one, true);
    };

    {
      let ratio = 79228162514264337593543950336000000;
      let tick = get_tick_at_sqrt_ratio(ratio);
      let ratio_of_tick = get_sqrt_ratio_at_tick(&tick);
      let ratio_of_tick_plus_one = get_sqrt_ratio_at_tick(&add(&tick, &one()));

      assert_eq(ratio >= ratio_of_tick, true);
      assert_eq(ratio < ratio_of_tick_plus_one, true);
    };

    {
      let ratio = 79228162514264337593543950336000;
      let tick = get_tick_at_sqrt_ratio(ratio);
      let ratio_of_tick = get_sqrt_ratio_at_tick(&tick);
      let ratio_of_tick_plus_one = get_sqrt_ratio_at_tick(&add(&tick, &one()));

      assert_eq(ratio >= ratio_of_tick, true);
      assert_eq(ratio < ratio_of_tick_plus_one, true);
    };

    {
      let ratio = 9903520314283042199192993792;
      let tick = get_tick_at_sqrt_ratio(ratio);
      let ratio_of_tick = get_sqrt_ratio_at_tick(&tick);
      let ratio_of_tick_plus_one = get_sqrt_ratio_at_tick(&add(&tick, &one()));

      assert_eq(ratio >= ratio_of_tick, true);
      assert_eq(ratio < ratio_of_tick_plus_one, true);
    };

    {
      let ratio = 28011385487393069959365969113;
      let tick = get_tick_at_sqrt_ratio(ratio);
      let ratio_of_tick = get_sqrt_ratio_at_tick(&tick);
      let ratio_of_tick_plus_one = get_sqrt_ratio_at_tick(&add(&tick, &one()));

      assert_eq(ratio >= ratio_of_tick, true);
      assert_eq(ratio < ratio_of_tick_plus_one, true);
    };

    {
      let ratio = 56022770974786139918731938227;
      let tick = get_tick_at_sqrt_ratio(ratio);
      let ratio_of_tick = get_sqrt_ratio_at_tick(&tick);
      let ratio_of_tick_plus_one = get_sqrt_ratio_at_tick(&add(&tick, &one()));

      assert_eq(ratio >= ratio_of_tick, true);
      assert_eq(ratio < ratio_of_tick_plus_one, true);
    };

    {
      let ratio = 79228162514264337593543950336;
      let tick = get_tick_at_sqrt_ratio(ratio);
      let ratio_of_tick = get_sqrt_ratio_at_tick(&tick);
      let ratio_of_tick_plus_one = get_sqrt_ratio_at_tick(&add(&tick, &one()));

      assert_eq(ratio >= ratio_of_tick, true);
      assert_eq(ratio < ratio_of_tick_plus_one, true);
    };

    {
      let ratio = 112045541949572279837463876454;
      let tick = get_tick_at_sqrt_ratio(ratio);
      let ratio_of_tick = get_sqrt_ratio_at_tick(&tick);
      let ratio_of_tick_plus_one = get_sqrt_ratio_at_tick(&add(&tick, &one()));

      assert_eq(ratio >= ratio_of_tick, true);
      assert_eq(ratio < ratio_of_tick_plus_one, true);
    };

    {
      let ratio = 224091083899144559674927752909;
      let tick = get_tick_at_sqrt_ratio(ratio);
      let ratio_of_tick = get_sqrt_ratio_at_tick(&tick);
      let ratio_of_tick_plus_one = get_sqrt_ratio_at_tick(&add(&tick, &one()));

      assert_eq(ratio >= ratio_of_tick, true);
      assert_eq(ratio < ratio_of_tick_plus_one, true);
    };

    {
      let ratio = 633825300114114700748351602688;
      let tick = get_tick_at_sqrt_ratio(ratio);
      let ratio_of_tick = get_sqrt_ratio_at_tick(&tick);
      let ratio_of_tick_plus_one = get_sqrt_ratio_at_tick(&add(&tick, &one()));

      assert_eq(ratio >= ratio_of_tick, true);
      assert_eq(ratio < ratio_of_tick_plus_one, true);
    };

    {
      let ratio = 79228162514264337593543950;
      let tick = get_tick_at_sqrt_ratio(ratio);
      let ratio_of_tick = get_sqrt_ratio_at_tick(&tick);
      let ratio_of_tick_plus_one = get_sqrt_ratio_at_tick(&add(&tick, &one()));

      assert_eq(ratio >= ratio_of_tick, true);
      assert_eq(ratio < ratio_of_tick_plus_one, true);
    };

    {
      let ratio = 79228162514264337593543;
      let tick = get_tick_at_sqrt_ratio(ratio);
      let ratio_of_tick = get_sqrt_ratio_at_tick(&tick);
      let ratio_of_tick_plus_one = get_sqrt_ratio_at_tick(&add(&tick, &one()));

      assert_eq(ratio >= ratio_of_tick, true);
      assert_eq(ratio < ratio_of_tick_plus_one, true);
    };

    {
      let ratio = 1461446703485210103287273052203988822378723970341;
      let tick = get_tick_at_sqrt_ratio(ratio);
      let ratio_of_tick = get_sqrt_ratio_at_tick(&tick);
      let ratio_of_tick_plus_one = get_sqrt_ratio_at_tick(&add(&tick, &one()));

      assert_eq(ratio >= ratio_of_tick, true);
      assert_eq(ratio < ratio_of_tick_plus_one, true);
    };
  }
}