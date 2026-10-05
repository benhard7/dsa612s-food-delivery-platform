import ballerina/time;
import ballerinax/mongodb;

final mongodb:Client mongoClient = check new ({connection: MONGO_URI});

// Action calls (->) aren't allowed in module-level initializers, so look collections up on demand.
function collection(string name) returns mongodb:Collection|error {
    mongodb:Database db = check mongoClient->getDatabase(MONGO_DB);
    return db->getCollection(name);
}

function nowIso() returns string => time:utcToString(time:utcNow());

// Each save returns true when the fact was new and false when it was a duplicate
// (Kafka delivers at least once, so repeats are normal).

function savePlaced(PlacedOrder p) returns boolean|error {
    mongodb:Collection col = check collection("placed_orders");
    PlacedOrder? existing = check col->findOne({orderId: p.orderId}, {}, {"_id": 0}, PlacedOrder);
    if existing is () {
        check col->insertOne(p);
        return true;
    }
    return false;
}

function saveCancelled(CancelledOrder c) returns boolean|error {
    mongodb:Collection col = check collection("cancelled_orders");
    CancelledOrder? existing = check col->findOne({orderId: c.orderId}, {}, {"_id": 0}, CancelledOrder);
    if existing is () {
        check col->insertOne(c);
        return true;
    }
    return false;
}

function saveDelivery(CompletedDelivery d) returns boolean|error {
    mongodb:Collection col = check collection("completed_deliveries");
    CompletedDelivery? existing = check col->findOne({orderId: d.orderId}, {}, {"_id": 0}, CompletedDelivery);
    if existing is () {
        check col->insertOne(d);
        return true;
    }
    return false;
}

function listPlaced() returns PlacedOrder[]|error {
    map<json> filter = {};
    mongodb:Collection col = check collection("placed_orders");
    stream<PlacedOrder, error?> result = check col->find(filter, {}, {"_id": 0}, PlacedOrder);
    return from PlacedOrder p in result
        select p;
}

function listCancelled() returns CancelledOrder[]|error {
    map<json> filter = {};
    mongodb:Collection col = check collection("cancelled_orders");
    stream<CancelledOrder, error?> result = check col->find(filter, {}, {"_id": 0}, CancelledOrder);
    return from CancelledOrder c in result
        select c;
}

function listDeliveries() returns CompletedDelivery[]|error {
    map<json> filter = {};
    mongodb:Collection col = check collection("completed_deliveries");
    stream<CompletedDelivery, error?> result = check col->find(filter, {}, {"_id": 0}, CompletedDelivery);
    return from CompletedDelivery d in result
        select d;
}
