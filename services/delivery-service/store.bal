import ballerina/time;
import ballerinax/mongodb;

final mongodb:Client mongoClient = check new ({connection: MONGO_URI});

// Action calls (->) aren't allowed in module-level initializers, so look collections up on demand.
function collection(string name) returns mongodb:Collection|error {
    mongodb:Database db = check mongoClient->getDatabase(MONGO_DB);
    return db->getCollection(name);
}

function nowIso() returns string => time:utcToString(time:utcNow());

function minutesSince(string isoStart) returns int {
    time:Utc|error began = time:utcFromString(isoStart);
    if began is error {
        return 1;
    }
    decimal secs = time:utcDiffSeconds(time:utcNow(), began);
    int m = <int>(secs / 60d);
    return m < 1 ? 1 : m;
}

// ---------- drivers ----------

function insertDriver(Driver d) returns error? {
    mongodb:Collection col = check collection("drivers");
    check col->insertOne(d);
}

function getDriver(string driverId) returns Driver|error? {
    mongodb:Collection col = check collection("drivers");
    return col->findOne({driverId: driverId}, {}, {"_id": 0}, Driver);
}

function listDrivers(string? status) returns Driver[]|error {
    map<json> filter = {};
    if status is string {
        filter["status"] = status;
    }
    mongodb:Collection col = check collection("drivers");
    stream<Driver, error?> result = check col->find(filter, {}, {"_id": 0}, Driver);
    return from Driver d in result
        select d;
}

// Atomically takes one AVAILABLE driver and marks them BUSY. Returns () if nobody is free.
// The update only matches while the driver is still AVAILABLE, so two deliveries
// can never claim the same driver.
function claimDriver() returns Driver|error? {
    Driver[] available = check listDrivers("AVAILABLE");
    mongodb:Collection col = check collection("drivers");
    foreach Driver d in available {
        mongodb:UpdateResult r = check col->updateOne(
            {driverId: d.driverId, status: "AVAILABLE"},
            {set: {status: "BUSY", updatedAt: nowIso()}}
        );
        if r.modifiedCount > 0 {
            return d;
        }
    }
    return ();
}

function freeDriver(string driverId) returns error? {
    mongodb:Collection col = check collection("drivers");
    _ = check col->updateOne({driverId: driverId, status: "BUSY"}, {set: {status: "AVAILABLE", updatedAt: nowIso()}});
}

// Manual AVAILABLE / OFFLINE switch; a BUSY driver cannot be switched.
function setDriverStatus(string driverId, string status) returns boolean|error {
    mongodb:Collection col = check collection("drivers");
    mongodb:UpdateResult r = check col->updateOne(
        {driverId: driverId, "status": {"$ne": "BUSY"}},
        {set: {status: status, updatedAt: nowIso()}}
    );
    return r.modifiedCount > 0 || r.matchedCount > 0;
}

// ---------- deliveries ----------

function insertDelivery(Delivery d) returns error? {
    mongodb:Collection col = check collection("deliveries");
    check col->insertOne(d);
}

function getDelivery(string deliveryId) returns Delivery|error? {
    mongodb:Collection col = check collection("deliveries");
    return col->findOne({deliveryId: deliveryId}, {}, {"_id": 0}, Delivery);
}

function getDeliveryByOrder(string orderId) returns Delivery|error? {
    mongodb:Collection col = check collection("deliveries");
    return col->findOne({orderId: orderId}, {}, {"_id": 0}, Delivery);
}

function listDeliveries(string? orderId, string? status, string? driverId) returns Delivery[]|error {
    map<json> filter = {};
    if orderId is string {
        filter["orderId"] = orderId;
    }
    if status is string {
        filter["status"] = status;
    }
    if driverId is string {
        filter["driverId"] = driverId;
    }
    mongodb:Collection col = check collection("deliveries");
    stream<Delivery, error?> result = check col->find(filter, {}, {"_id": 0}, Delivery);
    return from Delivery d in result
        select d;
}

// PENDING -> ASSIGNED, only if it is still PENDING (false if cancelled in the meantime)
function assignDriverToDelivery(string deliveryId, string driverId) returns boolean|error {
    mongodb:Collection col = check collection("deliveries");
    mongodb:UpdateResult r = check col->updateOne(
        {deliveryId: deliveryId, status: "PENDING"},
        {set: {status: "ASSIGNED", driverId: driverId, assignedAt: nowIso()}}
    );
    return r.modifiedCount > 0;
}

// ASSIGNED -> COMPLETED
function completeDelivery(string deliveryId, int durationMinutes) returns boolean|error {
    mongodb:Collection col = check collection("deliveries");
    mongodb:UpdateResult r = check col->updateOne(
        {deliveryId: deliveryId, status: "ASSIGNED"},
        {set: {status: "COMPLETED", completedAt: nowIso(), durationMinutes: durationMinutes}}
    );
    return r.modifiedCount > 0;
}

// PENDING | ASSIGNED -> CANCELLED. Returns the cancelled delivery, or () if there was nothing to cancel.
function cancelDelivery(string orderId) returns Delivery|error? {
    mongodb:Collection col = check collection("deliveries");
    mongodb:UpdateResult r = check col->updateOne(
        {orderId: orderId, "status": {"$in": ["PENDING", "ASSIGNED"]}},
        {set: {status: "CANCELLED", completedAt: nowIso()}}
    );
    if r.modifiedCount == 0 {
        return ();
    }
    return getDeliveryByOrder(orderId);
}

function updateLocation(string deliveryId, float lat, float lng) returns boolean|error {
    mongodb:Collection col = check collection("deliveries");
    mongodb:UpdateResult r = check col->updateOne(
        {deliveryId: deliveryId, status: "ASSIGNED"},
        {set: {lat: lat, lng: lng, locationUpdatedAt: nowIso()}}
    );
    return r.modifiedCount > 0;
}
