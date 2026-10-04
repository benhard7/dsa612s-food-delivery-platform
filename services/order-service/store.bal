import ballerinax/mongodb;

// One client for the lifetime of the service (a constructor is allowed at module level).
final mongodb:Client mongoClient = check new ({connection: mongoUri});

// Database and collection are fetched in a function because `->` calls
// are not allowed in module-level initializers. MongoDB creates them on first write.
function getOrderCol() returns mongodb:Collection|error {
    mongodb:Database db = check mongoClient->getDatabase(mongoDbName);
    return db->getCollection("orders");
}

function saveOrder(Order o) returns error? {
    mongodb:Collection col = check getOrderCol();
    check col->insertOne(o);
}

// Returns () when no order with that id exists.
function findOrder(string orderId) returns Order|error? {
    mongodb:Collection col = check getOrderCol();
    Order|mongodb:Error? result = col->findOne({orderId: orderId}, targetType = Order);
    return result;
}
