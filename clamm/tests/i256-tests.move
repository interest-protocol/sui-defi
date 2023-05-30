/// @notice Signed 256-bit integers in Move.
module clamm::i256_tests {

    use sui::test_utils::{assert_eq};
    use clamm::i256::{compare, from, neg_from, add, sub, zero, div, mul, shl, shr, one, min};

    const MAX_I256_AS_U256: u256 = (1 << 255) - 1;

    const U256_WITH_FIRST_BIT_SET: u256 = 1 << 255;

    const EQUAL: u8 = 0;

    const LESS_THAN: u8 = 1;

    const GREATER_THAN: u8 = 2;

    #[test]
    fun test_compare() {
        assert!(compare(&from(123), &from(123)) == EQUAL, 0);
        assert!(compare(&neg_from(123), &neg_from(123)) == EQUAL, 0);
        assert!(compare(&from(234), &from(123)) == GREATER_THAN, 0);
        assert!(compare(&from(123), &from(234)) == LESS_THAN, 0);
        assert!(compare(&neg_from(234), &neg_from(123)) == LESS_THAN, 0);
        assert!(compare(&neg_from(123), &neg_from(234)) == GREATER_THAN, 0);
        assert!(compare(&from(123), &neg_from(234)) == GREATER_THAN, 0);
        assert!(compare(&neg_from(123), &from(234)) == LESS_THAN, 0);
        assert!(compare(&from(234), &neg_from(123)) == GREATER_THAN, 0);
        assert!(compare(&neg_from(234), &from(123)) == LESS_THAN, 0);
    }

    #[test]
    fun test_add() {
        assert!(add(&from(123), &from(234)) == from(357), 0);
        assert!(add(&from(123), &neg_from(234)) == neg_from(111), 0);
        assert!(add(&from(234), &neg_from(123)) == from(111), 0);
        assert!(add(&neg_from(123), &from(234)) == from(111), 0);
        assert!(add(&neg_from(123), &neg_from(234)) == neg_from(357), 0);
        assert!(add(&neg_from(234), &neg_from(123)) == neg_from(357), 0);

        assert!(add(&from(123), &neg_from(123)) == zero(), 0);
        assert!(add(&neg_from(123), &from(123)) == zero(), 0);
    }

    #[test]
    fun test_sub() {
        assert!(sub(&from(123), &from(234)) == neg_from(111), 0);
        assert!(sub(&from(234), &from(123)) == from(111), 0);
        assert!(sub(&from(123), &neg_from(234)) == from(357), 0);
        assert!(sub(&neg_from(123), &from(234)) == neg_from(357), 0);
        assert!(sub(&neg_from(123), &neg_from(234)) == from(111), 0);
        assert!(sub(&neg_from(234), &neg_from(123)) == neg_from(111), 0);

        assert!(sub(&from(123), &from(123)) == zero(), 0);
        assert!(sub(&neg_from(123), &neg_from(123)) == zero(), 0);
    }

    #[test]
    fun test_mul() {
        assert!(mul(&from(123), &from(234)) == from(28782), 0);
        assert!(mul(&from(123), &neg_from(234)) == neg_from(28782), 0);
        assert!(mul(&neg_from(123), &from(234)) == neg_from(28782), 0);
        assert!(mul(&neg_from(123), &neg_from(234)) == from(28782), 0);
    }

    #[test]
    fun test_div() {
        assert!(div(&from(28781), &from(123)) == from(233), 0);
        assert!(div(&from(28781), &neg_from(123)) == neg_from(233), 0);
        assert!(div(&neg_from(28781), &from(123)) == neg_from(233), 0);
        assert!(div(&neg_from(28781), &neg_from(123)) == from(233), 0);
    }

    #[test]
    fun test_bit_shift() {
      assert_eq(compare(&min(), &shl(&one(), 255)), EQUAL);
      assert_eq(compare(&shr(&min(), 255), &one()), EQUAL);
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
}