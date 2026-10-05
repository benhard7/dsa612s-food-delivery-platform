import ballerina/log;
import ballerina/uuid;
import ballerinax/kafka;

final kafka:Producer producer = check new (KAFKA_BOOTSTRAP, {
    clientId: "delivery-service",
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

function publishAssigned(Delivery d) returns error? {
    json payload = {
        orderId: d.orderId,
        deliveryId: d.deliveryId,
        driverId: d.driverId,
        timestamp: d.assignedAt
    };
    check publish("delivery.assigned", d.orderId, payload);
}

function publishCompleted(Delivery d) returns error? {
    json payload = {
        orderId: d.orderId,
        deliveryId: d.deliveryId,
        driverId: d.driverId,
        durationMinutes: d.durationMinutes,
        timestamp: d.completedAt
    };
    check publish("delivery.completed", d.orderId, payload);
}

function notify(string recipientType, string recipientId, string channel, string orderId, string message) returns error? {
    json payload = {
        recipientType: recipientType,
        recipientId: recipientId,
        channel: channel,
        message: message,
        orderId: orderId,
        timestamp: nowIso()
    };
    check publish("notifications.send", orderId, payload);
}

// Claims a driver for the delivery. Returns false when nobody is free (delivery stays PENDING).
function tryAssign(Delivery d) returns boolean|error {
    Driver? driver = check claimDriver();
    if driver is () {
        return false;
    }
    boolean assigned = check assignDriverToDelivery(d.deliveryId, driver.driverId);
    if !assigned {
        check freeDriver(driver.driverId); // delivery was cancelled meanwhile
        return false;
    }
    Delivery? updated = check getDelivery(d.deliveryId);
    if updated is Delivery {
        check publishAssigned(updated);
        check notify("CUSTOMER", updated.customerId, "SMS", updated.orderId,
            "Your order " + updated.orderId + " is on its way with " + driver.name + ".");
        check notify("DRIVER", driver.driverId, "PUSH", updated.orderId,
            "New delivery: order " + updated.orderId + " to " + updated.deliveryAddress + ".");
        log:printInfo("delivery " + updated.deliveryId + " assigned to " + driver.driverId);
    }
    return true;
}

// Hands waiting deliveries to drivers who have become free, oldest delivery first.
function assignPending() returns error? {
    Delivery[] waiting = check listDeliveries((), "PENDING", ());
    // oldest first (ISO timestamps sort correctly as text)
    Delivery[] pending = from Delivery w in waiting
        order by w.createdAt ascending
        select w;
    foreach Delivery d in pending {
        boolean assigned = check tryAssign(d);
        if !assigned {
            break; // no drivers left
        }
    }
}

// orders.ready -> create a delivery and look for a driver
function handleOrderReady(OrderReadyEvent o) returns error? {
    Delivery? existing = check getDeliveryByOrder(o.orderId);
    if existing is Delivery {
        log:printWarn("duplicate orders.ready for " + o.orderId + ", already " + existing.status);
        return;
    }
    Delivery d = {
        deliveryId: "del-" + uuid:createType1AsString(),
        orderId: o.orderId,
        customerId: o.customerId,
        restaurantId: o.restaurantId,
        deliveryAddress: o.deliveryAddress,
        driverId: "",
        status: "PENDING",
        lat: 0.0,
        lng: 0.0,
        locationUpdatedAt: "",
        createdAt: nowIso(),
        assignedAt: "",
        completedAt: "",
        durationMinutes: 0
    };
    check insertDelivery(d);
    boolean assigned = check tryAssign(d);
    if !assigned {
        log:printInfo("no driver available for " + o.orderId + ", delivery is PENDING");
    }
}

// orders.cancelled -> drop the delivery and free the driver
function handleOrderCancelled(OrderRef o) returns error? {
    Delivery? c = check cancelDelivery(o.orderId);
    if c is Delivery {
        log:printInfo("delivery " + c.deliveryId + " cancelled with the order");
        if c.driverId != "" {
            check freeDriver(c.driverId);
            check assignPending();
        }
    }
}
