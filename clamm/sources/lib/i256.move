/// @notice Signed 256-bit integers in Move.
module clamm::i256 {

    const MAX_U256: u256 = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;

    const MAX_I256_AS_U256: u256 = (1 << 255) - 1;

    const U256_WITH_FIRST_BIT_SET: u256 = 1 << 255;

    const EQUAL: u8 = 0;

    const LESS_THAN: u8 = 1;

    const GREATER_THAN: u8 = 2;

    const ERROR_CONVERSION_FROM_U256_OVERFLOW: u64 = 0;
    const ERR0R_CONVERSION_TO_U256_UNDERFLOW: u64 = 1;

    struct I256 has copy, drop, store {
        bits: u256
    }

    public fun from_raw(x: u256): I256 {
      I256 { bits: x }
    }

    public fun one(): I256 {
      I256 { bits: 1 }
    }

    public fun min(): I256 {
      I256 { bits: 0x8000000000000000000000000000000000000000000000000000000000000000 }
    }

    public fun from(x: u256): I256 {
        assert!(x <= MAX_I256_AS_U256, ERROR_CONVERSION_FROM_U256_OVERFLOW);
        I256 { bits: x }
    }

    public fun zero(): I256 {
        I256 { bits: 0 }
    }

    public fun as_u256(x: &I256): u256 {
        assert!(x.bits < U256_WITH_FIRST_BIT_SET, ERR0R_CONVERSION_TO_U256_UNDERFLOW);
        x.bits
    }

    public fun is_zero(x: &I256): bool {
        x.bits == 0
    }

    public fun is_neg(x: &I256): bool {
        x.bits > U256_WITH_FIRST_BIT_SET
    }

    public fun neg(x: &I256): I256 {
        if (x.bits == 0) return *x;
        I256 { bits: if (x.bits < U256_WITH_FIRST_BIT_SET) x.bits | (1 << 255) else x.bits - (1 << 255) }
    }

    public fun neg_from(x: u256): I256 {
        let ret = from(x);
        if (ret.bits > 0) *&mut ret.bits = ret.bits | (1 << 255);
        ret
    }

    public fun abs(x: &I256): I256 {
        if (x.bits < U256_WITH_FIRST_BIT_SET) *x else I256 { bits: x.bits - (1 << 255) }
    }

    /// @notice Compare `a` and `b`.
    public fun compare(a: &I256, b: &I256): u8 {
        if (a.bits == b.bits) return EQUAL;
        if (a.bits < U256_WITH_FIRST_BIT_SET) {
            // A is positive
            if (b.bits < U256_WITH_FIRST_BIT_SET) {
                // B is positive
                return if (a.bits > b.bits) GREATER_THAN else LESS_THAN
            } else {
                // B is negative
                return GREATER_THAN
            }
        } else {
            // A is negative
            if (b.bits < U256_WITH_FIRST_BIT_SET) {
                // B is positive
                return LESS_THAN
            } else {
                // B is negative
                return if (a.bits > b.bits) LESS_THAN else GREATER_THAN
            }
        }
    }

    public fun add(a: &I256, b: &I256): I256 {
        if (a.bits >> 255 == 0) {
            // A is positive
            if (b.bits >> 255 == 0) {
                // B is positive
                return I256 { bits: a.bits + b.bits }
            } else {
                // B is negative
                if (b.bits - (1 << 255) <= a.bits) return I256 { bits: a.bits - (b.bits - (1 << 255)) }; // Return positive
                return I256 { bits: b.bits - a.bits } // Return negative
            }
        } else {
            // A is negative
            if (b.bits >> 255 == 0) {
                // B is positive
                if (a.bits - (1 << 255) <= b.bits) return I256 { bits: b.bits - (a.bits - (1 << 255)) }; // Return positive
                return I256 { bits: a.bits - b.bits } // Return negative
            } else {
                // B is negative
                return I256 { bits: a.bits + (b.bits - (1 << 255)) }
            }
        }
    }

    /// @notice Subtract `a - b`.
    public fun sub(a: &I256, b: &I256): I256 {
        if (a.bits >> 255 == 0) {
            // A is positive
            if (b.bits >> 255 == 0) {
                // B is positive
                if (a.bits >= b.bits) return I256 { bits: a.bits - b.bits }; // Return positive
                return I256 { bits: (1 << 255) | (b.bits - a.bits) } // Return negative
            } else {
                // B is negative
                return I256 { bits: a.bits + (b.bits - (1 << 255)) } // Return negative
            }
        } else {
            // A is negative
            if (b.bits >> 255 == 0) {
                // B is positive
                return I256 { bits: a.bits + b.bits } // Return negative
            } else {
                // B is negative
                if (b.bits >= a.bits) return I256 { bits: b.bits - a.bits }; // Return positive
                return I256 { bits: a.bits - (b.bits - (1 << 255)) } // Return negative
            }
        }
    }

    /// @notice Multiply `a * b`.
    public fun mul(a: &I256, b: &I256): I256 {
        if (a.bits >> 255 == 0) {
            // A is positive
            if (b.bits >> 255 == 0) {
                // B is positive
                return I256 { bits: a.bits * b.bits } // Return positive
            } else {
                // B is negative
                return I256 { bits: (1 << 255) | (a.bits * (b.bits - (1 << 255))) } // Return negative
            }
        } else {
            // A is negative
            if (b.bits >> 255 == 0) {
                // B is positive
                return I256 { bits: (1 << 255) | (b.bits * (a.bits - (1 << 255))) } // Return negative
            } else {
                // B is negative
                return I256 { bits: (a.bits - (1 << 255)) * (b.bits - (1 << 255)) } // Return positive
            }
        }
    }

    /// @notice Divide `a / b`.
    public fun div(a: &I256, b: &I256): I256 {
        if (a.bits >> 255 == 0) {
            // A is positive
            if (b.bits >> 255 == 0) {
                // B is positive
                return I256 { bits: a.bits / b.bits } // Return positive
            } else {
                // B is negative
                return I256 { bits: (1 << 255) | (a.bits / (b.bits - (1 << 255))) } // Return negative
            }
        } else {
            // A is negative
            if (b.bits >> 255 == 0) {
                // B is positive
                return I256 { bits: (1 << 255) | ((a.bits - (1 << 255)) / b.bits) } // Return negative
            } else {
                // B is negative
                return I256 { bits: (a.bits - (1 << 255)) / (b.bits - (1 << 255)) } // Return positive
            }
        }    
    }

    public fun shr(a: &I256, rhs: u8): I256 {
      // Perform the arithmetic right shift on the unsigned bits
      let result = a.bits >> rhs;

       I256 { bits: if (a.bits < U256_WITH_FIRST_BIT_SET) {
        result - (1 << 255) 
       } else {
         result
        }
       }
    }

    public fun shl(a: &I256, rhs: u8): I256 {
      I256 {
        bits: if (a.bits < U256_WITH_FIRST_BIT_SET) {
        a.bits << rhs
       } else {
         (a.bits << rhs) | (1 << 255)
        }
     } 
    }

    public fun or(a: &I256, b: &I256): I256 {
      I256 {
      bits: a.bits | b.bits
      } 
    }

     public fun and(a: &I256, b: &I256): I256 {
      I256 {
      bits: a.bits & b.bits
      } 
    }
}