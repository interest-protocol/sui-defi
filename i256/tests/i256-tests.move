#[test_only]
module i256::i256_tests {

    use sui::test_utils::{assert_eq};
    
    use i256::i256::{compare, from, neg_from, add, sub, zero, div, mul, shl, shr, abs, bits, or, and, is_neg, flip, is_positive, mod, truncate_to_u8, from_raw};

    const EQUAL: u8 = 0;

    const LESS_THAN: u8 = 1;

    const GREATER_THAN: u8 = 2;

    #[test]
    fun test_truncate_to_u8() {
      assert_eq(truncate_to_u8(&from(0x1234567890)), 0x90);
      assert_eq(truncate_to_u8(&from(0xABCDEF)), 0xEF);
      assert_eq(truncate_to_u8(&from_raw(115792089237316195423570985008687907853269984665640564039457584007913129639935)), 255);
      assert_eq(truncate_to_u8(&from_raw(256)), 0);
      assert_eq(truncate_to_u8(&from_raw(511)), 255);
      assert_eq(truncate_to_u8(&neg_from(230)), 26);
    }

    #[test]
    fun test_compare() {
        assert_eq(compare(&from(123), &from(123)), EQUAL);
        assert_eq(compare(&neg_from(123), &neg_from(123)), EQUAL);
        assert_eq(compare(&from(234), &from(123)), GREATER_THAN);
        assert_eq(compare(&from(123), &from(234)), LESS_THAN);
        assert_eq(compare(&neg_from(234), &neg_from(123)), LESS_THAN);
        assert_eq(compare(&neg_from(123), &neg_from(234)), GREATER_THAN);
        assert_eq(compare(&from(123), &neg_from(234)), GREATER_THAN);
        assert_eq(compare(&neg_from(123), &from(234)), LESS_THAN);
        assert_eq(compare(&from(234), &neg_from(123)), GREATER_THAN);
        assert_eq(compare(&neg_from(234), &from(123)), LESS_THAN);
    }

    #[test]
    fun test_add() {
        assert_eq(add(&from(123), &from(234)), from(357));
        assert_eq(add(&from(123), &neg_from(234)), neg_from(111));
        assert_eq(add(&from(234), &neg_from(123)), from(111));
        assert_eq(add(&neg_from(123), &from(234)), from(111));
        assert_eq(add(&neg_from(123), &neg_from(234)), neg_from(357));
        assert_eq(add(&neg_from(234), &neg_from(123)), neg_from(357));
        assert_eq(add(&from(123), &neg_from(123)), zero());
        assert_eq(add(&neg_from(123), &from(123)), zero());
    }

    #[test]
    fun test_sub() {
        assert_eq(sub(&from(123), &from(234)), neg_from(111));
        assert_eq(sub(&from(234), &from(123)), from(111));
        assert_eq(sub(&from(123), &neg_from(234)), from(357));
        assert_eq(sub(&neg_from(123), &from(234)), neg_from(357));
        assert_eq(sub(&neg_from(123), &neg_from(234)), from(111));
        assert_eq(sub(&neg_from(234), &neg_from(123)), neg_from(111));
        assert_eq(sub(&from(123), &from(123)), zero());
        assert_eq(sub(&neg_from(123), &neg_from(123)), zero());
    }

    #[test]
    fun test_mul() {
        assert_eq(mul(&from(123), &from(234)), from(28782));
        assert_eq(mul(&from(123), &neg_from(234)), neg_from(28782));
        assert_eq(mul(&neg_from(123), &from(234)), neg_from(28782));
        assert_eq(mul(&neg_from(123), &neg_from(234)), from(28782));
    }

    #[test]
    fun test_div() {
        assert_eq(div(&from(28781), &from(123)), from(233));
        assert_eq(div(&from(28781), &neg_from(123)), neg_from(233));
        assert_eq(div(&neg_from(28781), &from(123)), neg_from(233));
        assert_eq(div(&neg_from(28781), &neg_from(123)), from(233));
    }

    #[test]
    fun test_shl() {
      assert_eq(compare(&shl(&from(42), 0), &from(42)), EQUAL);
      assert_eq(compare(&shl(&from(42), 1), &from(84)), EQUAL);
      assert_eq(compare(&shl(&neg_from(42), 2), &neg_from(168)), EQUAL);
      assert_eq(compare(&shl(&zero(), 5), &zero()), EQUAL);
      assert_eq(compare(&shl(&from(42), 255), &zero()), EQUAL);
      assert_eq(compare(&shl(&from(5), 3), &from(40)), EQUAL);
      assert_eq(compare(&shl(&neg_from(5), 3), &neg_from(40)), EQUAL);
      assert_eq(compare(&shl(&neg_from(123456789), 5), &neg_from(3950617248)), EQUAL);
    }

    #[test]
    fun test_abs() {
      assert_eq(bits(&from(10)), bits(&abs(&neg_from(10))));
      assert_eq(bits(&from(12826189)), bits(&abs(&neg_from(12826189))));
      assert_eq(bits(&from(10)), bits(&abs(&from(10))));
      assert_eq(bits(&from(12826189)), bits(&abs(&from(12826189))));
      assert_eq(bits(&from(0)), bits(&abs(&from(0))));
    }

    #[test]
    fun test_neg_from() {
      assert_eq(bits(&neg_from(10)), 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF6);
      assert_eq(bits(&neg_from(100)), 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF9C);
    }

    #[test]
    fun test_shr() {
      assert_eq(shr(&neg_from(10), 1), neg_from(5));
      assert_eq(shr(&neg_from(25), 3), neg_from(4));
      assert_eq(shr(&neg_from(2147483648), 1), neg_from(1073741824));
      assert_eq(shr(&neg_from(123456789), 32), neg_from(1));
      assert_eq(shr(&neg_from(987654321), 40), neg_from(1));
      assert_eq(shr(&neg_from(42),100), neg_from(1));
      assert_eq(shr(&neg_from(0),100), neg_from(0));
      assert_eq(shr(&from(0),20), from(0));
    }

    #[test]
    fun test_or() {
      assert_eq(or(&zero(), &zero()), zero());
      assert_eq(or(&zero(), &neg_from(1)), neg_from(1));
      assert_eq(or(&neg_from(1), &neg_from(1)), neg_from(1));
      assert_eq(or(&neg_from(1), &from(1)), neg_from(1));
      assert_eq(or(&from(10), &from(5)), from(15));
      assert_eq(or(&neg_from(10), &neg_from(5)), neg_from(1));
      assert_eq(or(&neg_from(10), &neg_from(4)), neg_from(2));
    }

    #[test]
    fun test_is_neg() {
      assert_eq(is_neg(&zero()), false);
      assert_eq(is_neg(&neg_from(5)), true);
      assert_eq(is_neg(&from(172)), false);
    }

    #[test]
    fun test_flip() {
      assert_eq(flip(&zero()), zero());
      assert_eq(flip(&neg_from(5)), from(5));
      assert_eq(flip(&from(172)), neg_from(172));
    }

    #[test]
    fun test_is_positive() {
      assert_eq(is_positive(&zero()), true);
      assert_eq(is_positive(&neg_from(5)), false);
      assert_eq(is_positive(&from(172)), true);
    }

    #[test]
    fun test_and() {
       assert_eq(and(&zero(), &zero()), zero());
       assert_eq(and(&zero(), &neg_from(1)), zero());
       assert_eq(and(&neg_from(1), &neg_from(1)), neg_from(1));
       assert_eq(and(&neg_from(1), &from(1)), from(1));
       assert_eq(and(&from(10), &from(5)), zero());
       assert_eq(and(&neg_from(10), &neg_from(5)), neg_from(14));
    }

    #[test]
    fun test_mod() {
      assert_eq(mod(&neg_from(100), &neg_from(30)), neg_from(10));
      assert_eq(mod(&neg_from(100), &from(30)), neg_from(10));
      assert_eq(mod(&from(100), &neg_from(30)), from(10));
      assert_eq(mod(&from(100), &from(30)), from(10));
      assert_eq(mod(
        &from(1234567890123456789012345678901234567890), 
        &from(987654321)),
        from(792341811)
      );
    }
}