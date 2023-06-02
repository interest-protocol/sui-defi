#[test_only]
module clamm::tick_bit_map_tests {
  use sui::table;
  use sui::test_utils::{assert_eq, destroy}; 
  use sui::test_scenario::{Self, ctx};

  use i256::i256::{I256, from, neg_from, one};

  use clamm::tick_bit_map::{test_is_initialized as is_initialized, test_flip_tick as flip_tick, test_next_initialized_tick_within_one_word as next_initialized_tick_within_one_word, State};
  use clamm::test_utils::{scenario};


  #[test]
  fun test_is_initialized() {
    let scenario = scenario();
    let test = &mut scenario;

    {
    let bit_map = table::new<I256, State>(ctx(test));

    assert_eq(is_initialized(&mut bit_map, &one()), false);

    destroy(bit_map);
    };

    {
    let bit_map = table::new<I256, State>(ctx(test));

    flip_tick(&mut bit_map, &one());
    assert_eq(is_initialized(&mut bit_map, &one()), true);

    destroy(bit_map);
    };

    {
    let bit_map = table::new<I256, State>(ctx(test));

    flip_tick(&mut bit_map, &one());
    flip_tick(&mut bit_map, &one());
    assert_eq(is_initialized(&mut bit_map, &one()), false);

    destroy(bit_map);
    };

    {
    let bit_map = table::new<I256, State>(ctx(test));

    flip_tick(&mut bit_map, &from(257));
    assert_eq(is_initialized(&mut bit_map, &one()), false);
    assert_eq(is_initialized(&mut bit_map, &from(257)), true);

    destroy(bit_map);
    };

    test_scenario::end(scenario);
  }

  #[test]
  fun test_flip_tick() {
    let scenario = scenario();
    let test = &mut scenario;

    {
    let bit_map = table::new<I256, State>(ctx(test));

    flip_tick(&mut bit_map, &neg_from(230));

    assert_eq(is_initialized(&mut bit_map, &neg_from(230)), true);
    assert_eq(is_initialized(&mut bit_map, &neg_from(231)), false);
    assert_eq(is_initialized(&mut bit_map, &neg_from(229)), false);
    assert_eq(is_initialized(&mut bit_map, &from(26)), false);
    assert_eq(is_initialized(&mut bit_map, &neg_from(486)), false);

    flip_tick(&mut bit_map, &neg_from(230));

    assert_eq(is_initialized(&mut bit_map, &neg_from(230)), false);
    assert_eq(is_initialized(&mut bit_map, &neg_from(231)), false);
    assert_eq(is_initialized(&mut bit_map, &neg_from(229)), false);
    assert_eq(is_initialized(&mut bit_map, &from(26)), false);
    assert_eq(is_initialized(&mut bit_map, &neg_from(486)), false);

    destroy(bit_map);
    };

    {
      let bit_map = table::new<I256, State>(ctx(test));

      flip_tick(&mut bit_map, &neg_from(230));
      flip_tick(&mut bit_map, &neg_from(259));
      flip_tick(&mut bit_map, &neg_from(229));
      flip_tick(&mut bit_map, &from(500));
      flip_tick(&mut bit_map, &neg_from(259));
      flip_tick(&mut bit_map, &neg_from(229));
      flip_tick(&mut bit_map, &neg_from(259));

      assert_eq(is_initialized(&mut bit_map, &neg_from(259)), true);
      assert_eq(is_initialized(&mut bit_map, &neg_from(229)), false);
      
      destroy(bit_map);
    };

    test_scenario::end(scenario);
  }


  #[test]
  fun test_next_initialized_tick_within_one_word() {
    let scenario = scenario();
    let test = &mut scenario;
    let bit_map = table::new<I256, State>(ctx(test));
    
    {
      flip_tick(&mut bit_map, &neg_from(200));
      flip_tick(&mut bit_map, &neg_from(55));
      flip_tick(&mut bit_map, &neg_from(4));
      flip_tick(&mut bit_map, &from(70));
      flip_tick(&mut bit_map, &from(78));
      flip_tick(&mut bit_map, &from(84));
      flip_tick(&mut bit_map, &from(139));    
      flip_tick(&mut bit_map, &from(240));    
      flip_tick(&mut bit_map, &from(535));      
    };

    // LTE IS FALSE

    let (next, initialized) = next_initialized_tick_within_one_word(&mut bit_map, &from(78), false);

    assert_eq(next, from(84));
    assert_eq(initialized, true);


    let (next, initialized) = next_initialized_tick_within_one_word(&mut bit_map, &neg_from(55), false);

    assert_eq(next, neg_from(4));
    assert_eq(initialized, true);

    let (next, initialized) = next_initialized_tick_within_one_word(&mut bit_map, &from(77), false);

    assert_eq(next, from(78));
    assert_eq(initialized, true);


    let (next, initialized) = next_initialized_tick_within_one_word(&mut bit_map, &neg_from(56), false);

    assert_eq(next, neg_from(55));
    assert_eq(initialized, true);

    let (next, initialized) = next_initialized_tick_within_one_word(&mut bit_map, &from(255), false);

    assert_eq(next, from(511));
    assert_eq(initialized, false);

    let (next, initialized) = next_initialized_tick_within_one_word(&mut bit_map, &neg_from(257), false);

    assert_eq(next, neg_from(200));
    assert_eq(initialized, true);

    flip_tick(&mut bit_map, &from(340));
    let (next, initialized) = next_initialized_tick_within_one_word(&mut bit_map, &from(328), false);

    assert_eq(next, from(340));
    assert_eq(initialized, true);
    flip_tick(&mut bit_map, &from(340));

    let (next, initialized) = next_initialized_tick_within_one_word(&mut bit_map, &from(508), false);

    assert_eq(next, from(511));
    assert_eq(initialized, false); 

    let (next, initialized) = next_initialized_tick_within_one_word(&mut bit_map, &from(255), false);

    assert_eq(next, from(511));
    assert_eq(initialized, false); 

    let (next, initialized) = next_initialized_tick_within_one_word(&mut bit_map, &from(383), false);

    assert_eq(next, from(511));
    assert_eq(initialized, false); 


    // LTE IS TRUE

    let (next, initialized) = next_initialized_tick_within_one_word(&mut bit_map, &from(78), true);

    assert_eq(next, from(78));
    assert_eq(initialized, true); 


    let (next, initialized) = next_initialized_tick_within_one_word(&mut bit_map, &from(79), true);

    assert_eq(next, from(78));
    assert_eq(initialized, true); 

    let (next, initialized) = next_initialized_tick_within_one_word(&mut bit_map, &from(258), true);

    assert_eq(next, from(256));
    assert_eq(initialized, false); 

    let (next, initialized) = next_initialized_tick_within_one_word(&mut bit_map, &from(256), true);

    assert_eq(next, from(256));
    assert_eq(initialized, false); 

    let (next, initialized) = next_initialized_tick_within_one_word(&mut bit_map, &from(72), true);

    assert_eq(next, from(70));
    assert_eq(initialized, true); 

    let (next, initialized) = next_initialized_tick_within_one_word(&mut bit_map, &neg_from(257), true);

    assert_eq(next, neg_from(512));
    assert_eq(initialized, false); 

    let (next, initialized) = next_initialized_tick_within_one_word(&mut bit_map, &from(1023), true);

    assert_eq(next, from(768));
    assert_eq(initialized, false); 

    let (next, initialized) = next_initialized_tick_within_one_word(&mut bit_map, &from(900), true);

    assert_eq(next, from(768));
    assert_eq(initialized, false); 

    flip_tick(&mut bit_map, &from(329));
    let (next, initialized) = next_initialized_tick_within_one_word(&mut bit_map, &from(456), true);

    assert_eq(next, from(329));
    assert_eq(initialized, true); 
      
    destroy(bit_map);
    test_scenario::end(scenario);
  }
}