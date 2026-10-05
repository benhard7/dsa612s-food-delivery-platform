import ballerina/time;
import ballerinax/mongodb;

final mongodb:Client mongoClient = check new ({connection: MONGO_URI});

// Action calls (->) aren't allowed in module-level initializers, so look collections up on demand.
function collection(string name) returns mongodb:Collection|error {
    mongodb:Database db = check mongoClient->getDatabase(MONGO_DB);
    return db->getCollection(name);
}

function nowIso() returns string => time:utcToString(time:utcNow());

function insertNotification(Notification n) returns error? {
    mongodb:Collection col = check collection("notifications");
    check col->insertOne(n);
}

function findByDedupe(string dedupeKey) returns Notification|error? {
    mongodb:Collection col = check collection("notifications");
    return col->findOne({dedupeKey: dedupeKey}, {}, {"_id": 0}, Notification);
}

function getNotification(string notificationId) returns Notification|error? {
    mongodb:Collection col = check collection("notifications");
    return col->findOne({notificationId: notificationId}, {}, {"_id": 0}, Notification);
}

function listNotifications(string? orderId, string? recipientId, string? recipientType,
        string? channel, string? status) returns Notification[]|error {
    map<json> filter = {};
    if orderId is string {
        filter["orderId"] = orderId;
    }
    if recipientId is string {
        filter["recipientId"] = recipientId;
    }
    if recipientType is string {
        filter["recipientType"] = recipientType;
    }
    if channel is string {
        filter["channel"] = channel;
    }
    if status is string {
        filter["status"] = status;
    }
    mongodb:Collection col = check collection("notifications");
    stream<Notification, error?> result = check col->find(filter, {}, {"_id": 0}, Notification);
    Notification[] all = check from Notification n in result
        select n;
    // oldest first
    return from Notification n in all
        order by n.createdAt ascending
        select n;
}

function saveIndex(OrderIndex idx) returns error? {
    mongodb:Collection col = check collection("order_index");
    OrderIndex? existing = check col->findOne({orderId: idx.orderId}, {}, {"_id": 0}, OrderIndex);
    if existing is () {
        check col->insertOne(idx);
    }
}

function lookupIndex(string orderId) returns OrderIndex|error? {
    mongodb:Collection col = check collection("order_index");
    return col->findOne({orderId: orderId}, {}, {"_id": 0}, OrderIndex);
}
