// Dummy Oracle 
module oracle::ipx_oracle {

  use std::ascii::{String};

  use library::utils::{get_type_name_string};

  const SCALAR: u256 = 1000000000000000000; // 1e18

  // Hot Potato to be passed. IMPORTANT DO NOT ADD ABILITIES
  // A Consumer contract needs to destroy it with read_price and assert the coin_name 
  struct Price {
    switchboard_result: u256,
    pyth_result: u256,
    scalar: u256,
    pyth_timestamp: u64,
    switchboard_timestamp: u64,
    average: u256, // average between pyth and switchboard prices
    coin_name: String
  }

  /**
  * @notice This function destroys the Price hot potato to be consumed. The consumer must assert that the coin_name is correct
  * @return (switchboard_result, pyth_result, scalar, average, pyth_timestamp, switchboard_timestamp, coin_name)
  */
  public fun read_price(price: Price): (u256, u256, u256, u256, u64, u64, String) {
    let Price { switchboard_result, pyth_result, scalar, pyth_timestamp, switchboard_timestamp, average, coin_name } = price;
    (average, switchboard_result, pyth_result, scalar, pyth_timestamp, switchboard_timestamp, coin_name)
  }


  #[test_only]
  public fun get_price_for_testing<T>(
    switchboard_result: u256,
    switchboard_timestamp: u64,
    pyth_result: u256,
    pyth_timestamp: u64,
    average: u256,
  ): Price {
    Price {
      switchboard_result,
      switchboard_timestamp,
      pyth_timestamp,
      pyth_result,
      average,
      scalar: SCALAR,
      coin_name: get_type_name_string<T>()
    }
  }
}