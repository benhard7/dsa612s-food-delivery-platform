import ballerina/log;
import ballerinax/kafka;

final kafka:Producer producer = check new (KAFKA_BOOTSTRAP, {
    clientId: "restaurant-service",
    acks: "all",
    retryCount: 3
});

// Key = orderId so all events of one order land in the same partition (ordered).
function publish(string topic, string orderId, json payload) returns error? {
    check producer->send({
        topic: topic,
        key: orderId.toBytes(),
        value: payload.toJsonString().toBytes()
    });
}

// status: PREPARING | READY | REJECTED (REJECTED makes Order Service cancel the order)
function publishStatusUpdate(string orderId, string restaurantId, string status, string reason) returns error? {
    json payload = {
        orderId: orderId,
        restaurantId: restaurantId,
        status: status,
        reason: reason == "" ? () : reason,
        timestamp: nowIso()
    };
    check publish("orders.status.updated", orderId, payload);
}

function notify(string recipientType, string recipientId, string orderId, string message) returns error? {
    json payload = {
        recipientType: recipientType,
        recipientId: recipientId,
        channel: "PUSH",
        message: message,
        orderId: orderId,
        timestamp: nowIso()
    };
    check publish("notifications.send", orderId, payload);
}

// orders.created -> reserve stock, or reject the order
function handleOrderCreated(OrderCreatedEvent o) returns error? {
    KitchenOrder? existing = check getKitchenOrder(o.orderId);
    if existing is KitchenOrder {
        log:printWarn("duplicate orders.created for " + o.orderId + ", already " + existing.status);
        return;
    }
    string status = "RESERVED";
    string reason = "";
    Restaurant? rest = check getRestaurant(o.restaurantId);
    if rest is () {
        status = "REJECTED";
        reason = "unknown restaurant " + o.restaurantId;
    } else {
        error? reserved = reserveAll(o.restaurantId, o.items);
        if reserved is StockError {
            status = "REJECTED";
            reason = reserved.message();
        } else if reserved is error {
            return reserved;
        }
    }
    string now = nowIso();
    KitchenOrder k = {
        orderId: o.orderId,
        customerId: o.customerId,
        restaurantId: o.restaurantId,
        items: o.items,
        status: status,
        reason: reason,
        createdAt: now,
        updatedAt: now
    };
    check insertKitchenOrder(k);
    log:printInfo("kitchen order " + o.orderId + ": " + status + (reason == "" ? "" : " (" + reason + ")"));
    if status == "REJECTED" {
        check publishStatusUpdate(o.orderId, o.restaurantId, "REJECTED", reason);
    }
}

// orders.confirmed -> payment received, the kitchen may start
function handleOrderConfirmed(OrderRef o) returns error? {
    KitchenOrder? k = check moveKitchen(o.orderId, ["RESERVED"], "CONFIRMED", "payment received");
    if k is KitchenOrder {
        check notify("RESTAURANT", k.restaurantId, k.orderId, "New confirmed order " + k.orderId + " - start preparing.");
    }
}

// orders.cancelled -> put the reserved stock back
function handleOrderCancelled(OrderRef o) returns error? {
    KitchenOrder? k = check moveKitchen(o.orderId, ["RESERVED", "CONFIRMED", "PREPARING", "READY"], "CANCELLED", "order cancelled");
    if k is KitchenOrder {
        releaseAll(k.restaurantId, k.items);
        log:printInfo("stock returned for cancelled order " + k.orderId);
    }
}
