module whirpool::controller {

  friend whirpool::itoken;


  public(friend) fun deposit_allowed<T>(): bool {
    true
  }

  public(friend) fun withdraw_allowed<T>(): bool {
    true
  }

  public(friend) fun borrow_allowed<T>(): bool {
    true
  }

  public(friend) fun repay_allowed<T>(): bool {
    true
  }
}