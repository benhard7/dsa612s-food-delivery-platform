import ballerina/log;
import ballerina/time;
import ballerinax/mongodb;

final mongodb:Client mongoClient = check new ({connection: MONGO_URI});

// Action calls (->) aren't allowed in module-level initializers, so look collections up on demand.
function collection(string name) returns mongodb:Collection|error {
    mongodb:Database db = check mongoClient->getDatabase(MONGO_DB);
    return db->getCollection(name);
}

function nowIso() returns string => time:utcToString(time:utcNow());

// ---------- opening hours ----------

function toMinutes(string hhmm) returns int|error {
    if hhmm.length() != 5 || hhmm.substring(2, 3) != ":" {
        return error("expected HH:MM");
    }
    int h = check int:fromString(hhmm.substring(0, 2));
    int m = check int:fromString(hhmm.substring(3, 5));
    if h > 23 || m > 59 {
        return error("expected HH:MM");
    }
    return h * 60 + m;
}

function validHours(string hhmm) returns boolean => toMinutes(hhmm) is int;

function isOpenNow(string openTime, string closeTime) returns boolean {
    int|error o = toMinutes(openTime);
    if o is error {
        return false;
    }
    int|error c = toMinutes(closeTime);
    if c is error {
        return false;
    }
    time:Civil civil = time:utcToCivil(time:utcAddSeconds(time:utcNow(), <decimal>(UTC_OFFSET_HOURS * 3600)));
    int now = civil.hour * 60 + civil.minute;
    return o <= c ? (now >= o && now < c) : (now >= o || now < c);
}

function toView(Restaurant r) returns RestaurantView =>
    {...r, openNow: isOpenNow(r.openTime, r.closeTime)};

// ---------- restaurants ----------

function insertRestaurant(Restaurant r) returns error? {
    mongodb:Collection col = check collection("restaurants");
    check col->insertOne(r);
}

function getRestaurant(string restaurantId) returns Restaurant|error? {
    mongodb:Collection col = check collection("restaurants");
    return col->findOne({restaurantId: restaurantId}, {}, {"_id": 0}, Restaurant);
}

function listRestaurants() returns Restaurant[]|error {
    mongodb:Collection col = check collection("restaurants");
    stream<Restaurant, error?> result = check col->find({}, {}, {"_id": 0}, Restaurant);
    return from Restaurant r in result
        select r;
}

function updateHours(string restaurantId, string openTime, string closeTime) returns boolean|error {
    mongodb:Collection col = check collection("restaurants");
    mongodb:UpdateResult r = check col->updateOne({restaurantId: restaurantId},
        {set: {openTime: openTime, closeTime: closeTime}});
    return r.matchedCount > 0;
}

// ---------- menu & inventory ----------

function insertMenuItem(MenuItem item) returns error? {
    mongodb:Collection col = check collection("menu_items");
    check col->insertOne(item);
}

function getMenuItem(string restaurantId, string itemId) returns MenuItem|error? {
    mongodb:Collection col = check collection("menu_items");
    return col->findOne({restaurantId: restaurantId, itemId: itemId}, {}, {"_id": 0}, MenuItem);
}

function listMenu(string restaurantId) returns MenuItem[]|error {
    mongodb:Collection col = check collection("menu_items");
    stream<MenuItem, error?> result = check col->find({restaurantId: restaurantId}, {}, {"_id": 0}, MenuItem);
    return from MenuItem m in result
        select m;
}

function setStock(string restaurantId, string itemId, int stock) returns boolean|error {
    mongodb:Collection col = check collection("menu_items");
    mongodb:UpdateResult r = check col->updateOne({restaurantId: restaurantId, itemId: itemId},
        {set: {stock: stock}});
    return r.matchedCount > 0;
}

// Compare-and-set on the current stock so two orders can never oversell the same item.
// Returns false if the item is unknown or the change would take stock below zero.
function adjustStock(string restaurantId, string itemId, int delta) returns boolean|error {
    mongodb:Collection col = check collection("menu_items");
    int attempts = 0;
    while attempts < 5 {
        MenuItem? item = check getMenuItem(restaurantId, itemId);
        if item is () {
            return false;
        }
        int newStock = item.stock + delta;
        if newStock < 0 {
            return false;
        }
        mongodb:UpdateResult r = check col->updateOne(
            {restaurantId: restaurantId, itemId: itemId, stock: item.stock},
            {set: {stock: newStock}}
        );
        if r.modifiedCount > 0 {
            return true;
        }
        attempts += 1; // someone else changed the stock in between; try again
    }
    return false;
}

function releaseAll(string restaurantId, OrderLine[] lines) {
    foreach OrderLine l in lines {
        boolean|error back = adjustStock(restaurantId, l.itemId, l.qty);
        if back is error || !back {
            log:printError("could not return stock for " + l.itemId);
        }
    }
}

// All-or-nothing: if any line can't be reserved, everything reserved so far is put back.
function reserveAll(string restaurantId, OrderLine[] lines) returns error? {
    OrderLine[] done = [];
    foreach OrderLine l in lines {
        boolean|error ok = adjustStock(restaurantId, l.itemId, -l.qty);
        if ok is error {
            releaseAll(restaurantId, done);
            return ok;
        }
        if !ok {
            releaseAll(restaurantId, done);
            return error StockError("insufficient stock or unknown item: " + l.itemId);
        }
        done.push(l);
    }
}

// ---------- kitchen orders ----------

function insertKitchenOrder(KitchenOrder k) returns error? {
    mongodb:Collection col = check collection("kitchen_orders");
    check col->insertOne(k);
}

function getKitchenOrder(string orderId) returns KitchenOrder|error? {
    mongodb:Collection col = check collection("kitchen_orders");
    return col->findOne({orderId: orderId}, {}, {"_id": 0}, KitchenOrder);
}

function listKitchenOrders(string? restaurantId, string? status) returns KitchenOrder[]|error {
    map<json> filter = {};
    if restaurantId is string {
        filter["restaurantId"] = restaurantId;
    }
    if status is string {
        filter["status"] = status;
    }
    mongodb:Collection col = check collection("kitchen_orders");
    stream<KitchenOrder, error?> result = check col->find(filter, {}, {"_id": 0}, KitchenOrder);
    return from KitchenOrder k in result
        select k;
}

// Moves a kitchen order to toStatus only if it is currently in one of fromStatuses.
// Returns () when the order is missing or in the wrong state (also covers duplicate events).
function moveKitchen(string orderId, string[] fromStatuses, string toStatus, string reason) returns KitchenOrder|error? {
    mongodb:Collection col = check collection("kitchen_orders");
    mongodb:UpdateResult r = check col->updateOne(
        {orderId: orderId, "status": {"$in": fromStatuses}},
        {set: {status: toStatus, reason: reason, updatedAt: nowIso()}}
    );
    if r.modifiedCount == 0 {
        return ();
    }
    return getKitchenOrder(orderId);
}
