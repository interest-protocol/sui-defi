module whirpool::controller {

  friend whirpool::itoken;


  public(friend) fun deposit_allowed<T>(): bool {
    true
  }
}