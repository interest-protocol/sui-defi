module interest_protocol::utils {
    
    use std::type_name::{Self};
    use std::ascii::{String};

    public fun get_coin_info<T>(): String {
       type_name::into_string(type_name::get<T>())
    }
}