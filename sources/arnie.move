module interest_protocol::todo {

    use sui::object::{UID};
    use std::vector;
    use std::string::String;
    use sui::table::{Self, Table};

    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    
    struct TodoObject has store{
        id: UID,
        taskID: u64,
        taskName: String,
        checked: bool,
        deleted: bool
    } 

    fun init(ctx: &mut TxContext){
        let userTable = table::new<address, vector<TodoObject>>(ctx);
        transfer::share_object(userTable); 
        // The object needs to be shared otherwise only the owner can modify the table object
        // If it's a shared object, people should be allowed to change only their mapping
    }

    public entry fun retrieveTasks(userTable: &mut Table<address, vector<TodoObject>>, ctx: &mut TxContext): &vector<TodoObject>{
         
         // Get user from TxContext
        let user = tx_context::sender(ctx);

        // Add a mapping for the user if it doesn't exist
        if(!table::contains(userTable, user)){
        
            table::add(userTable, user, vector::empty<TodoObject>());

        };
        table::borrow(userTable, user)
    }

}