#[test_only]
module library::math_tests {

    use library::math::{Self, exp, sqrt, fdiv_u256, sqrt_rounding, d_fdiv, d_fdiv_u256, mul_div_u128, mul_div};

    #[test]
    #[expected_failure(abort_code = library::math::ERROR_ZERO_DIVISION)]
    fun test_zero_division_error_fdiv_u256() {
      fdiv_u256(1, 0);
    }

    #[test]
    #[expected_failure(abort_code = library::math::ERROR_ZERO_DIVISION)]
    fun test_zero_division_error_d_fdiv() {
      d_fdiv(1, 0);
    }

    #[test]
    #[expected_failure(abort_code = library::math::ERROR_ZERO_DIVISION)]
    fun test_zero_division_error_d_fdiv_u256() {
      d_fdiv_u256(1, 0);
    }

    #[test]
    #[expected_failure(abort_code = library::math::ERROR_ZERO_DIVISION)]
    fun test_zero_division_error_mul_div_u128() {
      mul_div_u128(1, 1, 0);
    }

    #[test]
    #[expected_failure(abort_code = library::math::ERROR_ZERO_DIVISION)]
    fun test_zero_division_error_mul_div() {
      mul_div(1, 1, 0);
    }

    #[test]
    fun test_exp() {
        assert!(exp(0, 0) == 1, 0); // TODO: Should this be undefined?
        assert!(exp(0, 1) == 0, 1);
        assert!(exp(0, 5) == 0, 2);

        assert!(exp(1, 0) == 1, 3);
        assert!(exp(1, 1) == 1, 4);
        assert!(exp(1, 5) == 1, 5);

        assert!(exp(2, 0) == 1, 6);
        assert!(exp(2, 1) == 2, 7);
        assert!(exp(2, 5) == 32, 8);
        
        assert!(exp(123, 0) == 1, 9);
        assert!(exp(123, 1) == 123, 10);
        assert!(exp(123, 5) == 28153056843, 11);

        assert!(exp(45, 6) == 8303765625, 12);
    }

    #[test]
    fun test_sqrt() {
        let rounding_up = math::get_rounding_down();

        assert!(sqrt(0) == 0, 0);
        assert!(sqrt(1) == 1, 1);

        assert!(sqrt(2) == 1, 2);
        assert!(sqrt_rounding(2, rounding_up) == 2, 3);

        assert!(sqrt(169) == 13, 4);
        assert!(sqrt_rounding(169, rounding_up) == 13, 5);
        assert!(sqrt_rounding(170, rounding_up) == 14, 6);
        assert!(sqrt(195) == 13, 7);
        assert!(sqrt(196) == 14, 8);

        assert!(sqrt(55423988929) == 235423, 9);
        assert!(sqrt_rounding(55423988929, rounding_up) == 235423, 10);
        assert!(sqrt(55423988930) == 235423, 11);
        assert!(sqrt_rounding(55423988930, rounding_up) == 235424, 12);
    }
}