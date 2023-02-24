module interest_protocol::utils {
    
    use std::type_name::{Self};
    use std::ascii::{String};

    // TODO: need to update to timestamps whenever they are implemented in the devnet
    const EPOCHS_PER_YEAR: u64 = 3504; // 24 / 2.5 * 365

    public fun get_coin_info<T>(): String {
       type_name::into_string(type_name::get<T>())
    }

    public fun get_epochs_per_year(): u64 {
        EPOCHS_PER_YEAR
    }
}