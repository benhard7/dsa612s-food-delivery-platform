import ballerina/time;
import ballerinax/mongodb;

final mongodb:Client mongoClient = check new ({connection: MONGO_URI});

// Action calls (->) aren't allowed in module-level initializers, so look collections up on demand.
function collection(string name) returns mongodb:Collection|error {
    mongodb:Database db = check mongoClient->getDatabase(MONGO_DB);
    return db->getCollection(name);
}

function nowIso() returns string => time:utcToString(time:utcNow());

function insertPayment(Payment p) returns error? {
    mongodb:Collection payments = check collection("payments");
    check payments->insertOne(p);
}

function getPayment(string paymentId) returns Payment|error? {
    mongodb:Collection payments = check collection("payments");
    return payments->findOne({paymentId: paymentId}, {}, {"_id": 0}, Payment);
}

function findByOrderId(string orderId) returns Payment|error? {
    mongodb:Collection payments = check collection("payments");
    return payments->findOne({orderId: orderId}, {}, {"_id": 0}, Payment);
}

function listPayments(string? orderId, string? status) returns Payment[]|error {
    map<json> filter = {};
    if orderId is string {
        filter["orderId"] = orderId;
    }
    if status is string {
        filter["status"] = status;
    }
    mongodb:Collection payments = check collection("payments");
    stream<Payment, error?> result = check payments->find(filter, {}, {"_id": 0}, Payment);
    return from Payment p in result
        select p;
}

// COMPLETED -> REFUNDED. Returns () when there was nothing to refund
// (e.g. the payment had FAILED, or the event was a duplicate).
function refundForOrder(string orderId) returns Payment|error? {
    mongodb:Collection payments = check collection("payments");
    mongodb:UpdateResult r = check payments->updateOne(
        {orderId: orderId, status: "COMPLETED"},
        {set: {status: "REFUNDED", reason: "order cancelled", updatedAt: nowIso()}}
    );
    if r.modifiedCount == 0 {
        return ();
    }
    return findByOrderId(orderId);
}
