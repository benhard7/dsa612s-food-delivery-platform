import ballerina/time;
import ballerinax/mongodb;

final mongodb:Client mongoClient = check new ({connection: MONGO_URI});

// Action calls (->) aren't allowed in module-level initializers, so look collections up on demand.
function collection(string name) returns mongodb:Collection|error {
    mongodb:Database db = check mongoClient->getDatabase(MONGO_DB);
    return db->getCollection(name);
}

// Order state machine (see docs/events.md)
final map<string[]> ALLOWED = {
    "CREATED": ["CONFIRMED", "CANCELLED"],
    "CONFIRMED": ["PREPARING", "CANCELLED"],
    "PREPARING": ["READY", "CANCELLED"],
    "READY": ["OUT_FOR_DELIVERY", "CANCELLED"],
    "OUT_FOR_DELIVERY": ["DELIVERED"],
    "DELIVERED": [],
    "CANCELLED": []
};

function nowIso() returns string => time:utcToString(time:utcNow());

function canTransition(string fromStatus, string toStatus) returns boolean {
    string[]? next = ALLOWED[fromStatus];
    return next is string[] && next.indexOf(toStatus) is int;
}

function insertOrder(Order o) returns error? {
    mongodb:Collection orders = check collection("orders");
    check orders->insertOne(o);
    check logChange(o.orderId, "-", o.status, "order placed");
}

function logChange(string orderId, string fromStatus, string toStatus, string reason) returns error? {
    StatusChange change = {orderId, fromStatus, toStatus, reason, timestamp: nowIso()};
    mongodb:Collection orderEvents = check collection("order_events");
    check orderEvents->insertOne(change);
}

// projection {_id: 0} so documents map cleanly onto the closed Order record
function getOrder(string orderId) returns Order|error? {
    mongodb:Collection orders = check collection("orders");
    return orders->findOne({orderId: orderId}, {}, {"_id": 0}, Order);
}

function listOrders(string? customerId, string? status) returns Order[]|error {
    map<json> filter = {};
    if customerId is string {
        filter["customerId"] = customerId;
    }
    if status is string {
        filter["status"] = status;
    }
    mongodb:Collection orders = check collection("orders");
    stream<Order, error?> result = check orders->find(filter, {}, {"_id": 0}, Order);
    return from Order o in result
        select o;
}

function getHistory(string orderId) returns StatusChange[]|error {
    mongodb:Collection orderEvents = check collection("order_events");
    stream<StatusChange, error?> result = check orderEvents->find({orderId: orderId}, {}, {"_id": 0}, StatusChange);
    return from StatusChange c in result
        select c;
}

// Validates the transition, then updates with a compare-and-set on the current status
// so two concurrent events can never both win.
function applyTransition(string orderId, string toStatus, string reason) returns Order|error {
    Order? current = check getOrder(orderId);
    if current is () {
        return error OrderNotFoundError("order " + orderId + " not found");
    }
    if !canTransition(current.status, toStatus) {
        return error InvalidTransitionError(string `cannot move ${orderId} from ${current.status} to ${toStatus}`);
    }
    mongodb:Collection orders = check collection("orders");
    mongodb:UpdateResult r = check orders->updateOne(
        {orderId: orderId, status: current.status},
        {set: {status: toStatus, updatedAt: nowIso()}}
    );
    if r.modifiedCount == 0 {
        return error InvalidTransitionError("concurrent update on " + orderId + ", please retry");
    }
    check logChange(orderId, current.status, toStatus, reason);
    Order? updated = check getOrder(orderId);
    return updated ?: error OrderNotFoundError("order " + orderId + " not found");
}
