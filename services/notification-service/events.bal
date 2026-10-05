import ballerina/log;
import ballerina/uuid;
import ballerinax/kafka;

final kafka:Producer producer = check new (KAFKA_BOOTSTRAP, {
    clientId: "notification-service",
    acks: "all",
    retryCount: 3
});

// Key = orderId so all events of one order land in the same partition (ordered).
function publish(string topic, string orderId, json payload) returns error? {
    check producer->send({
        topic: topic,
        key: (orderId == "" ? uuid:createType1AsString() : orderId).toBytes(),
        value: payload.toJsonString().toBytes()
    });
}

// Simulated gateway: a real system would call an email / SMS / push provider here.
// Returns a failure reason, or "" when delivered.
function dispatch(string channel, string recipientType, string recipientId, string message) returns string {
    if recipientId.trim() == "" {
        return "no recipient";
    }
    log:printInfo(string `[${channel}] -> ${recipientType} ${recipientId}: ${message}`);
    return "";
}

// Validates, "sends" and stores one notification. Idempotent on dedupeKey, so Kafka redeliveries
// never alert someone twice.
function sendNotification(string dedupeKey, string recipientType, string recipientId, string channel,
        string message, string orderId, string 'source) returns error? {
    Notification? existing = check findByDedupe(dedupeKey);
    if existing is Notification {
        log:printWarn("duplicate notification ignored: " + dedupeKey);
        return;
    }
    string status = "SENT";
    string reason = "";
    if VALID_RECIPIENTS.indexOf(recipientType) is () {
        status = "FAILED";
        reason = "unsupported recipientType " + recipientType;
    } else if VALID_CHANNELS.indexOf(channel) is () {
        status = "FAILED";
        reason = "unsupported channel " + channel;
    } else {
        reason = dispatch(channel, recipientType, recipientId, message);
        if reason != "" {
            status = "FAILED";
        }
    }
    Notification n = {
        notificationId: "ntf-" + uuid:createType1AsString(),
        dedupeKey: dedupeKey,
        recipientType: recipientType,
        recipientId: recipientId,
        channel: channel,
        message: message,
        orderId: orderId,
        'source: 'source,
        status: status,
        reason: reason,
        createdAt: nowIso()
    };
    check insertNotification(n);
    if status == "FAILED" {
        log:printWarn("notification " + n.notificationId + " FAILED: " + reason);
    }
}

// Notification triggered by a lifecycle event: at most one per (topic, order, recipient type).
function lifecycle(string topic, string orderId, string recipientType, string recipientId,
        string channel, string message) returns error? {
    check sendNotification(topic + "|" + orderId + "|" + recipientType, recipientType, recipientId,
        channel, message, orderId, topic);
}

// notifications.send: another service asked us to alert someone directly
function handleDirect(NotificationRequest r) returns error? {
    string directKey = "direct|" + r.orderId + "|" + r.recipientType + "|" + r.recipientId + "|" + r.channel + "|" + r.message;
    check sendNotification(directKey, r.recipientType, r.recipientId, r.channel, r.message, r.orderId, "notifications.send");
}

function handleOrderCreated(OrderEvent e) returns error? {
    check saveIndex({orderId: e.orderId, customerId: e.customerId, restaurantId: e.restaurantId});
    check lifecycle("orders.created", e.orderId, "CUSTOMER", e.customerId, "EMAIL",
        string `We received your order ${e.orderId} (total N$ ${e.total}).`);
}

function handlePayment(string topic, PaymentEvent e) returns error? {
    OrderIndex? idx = check lookupIndex(e.orderId);
    string customerId = idx is OrderIndex ? idx.customerId : "unknown";
    if topic == "payments.completed" {
        check lifecycle(topic, e.orderId, "CUSTOMER", customerId, "EMAIL",
            string `Payment of N$ ${e.amount} received for order ${e.orderId}.`);
    } else {
        string why = e.reason ?: "payment declined";
        check lifecycle(topic, e.orderId, "CUSTOMER", customerId, "EMAIL",
            string `Payment for order ${e.orderId} failed (${why}). The order was cancelled.`);
    }
}

function handleOrderStatus(string topic, OrderEvent e) returns error? {
    match topic {
        "orders.confirmed" => {
            check lifecycle(topic, e.orderId, "CUSTOMER", e.customerId, "SMS",
                string `Your order ${e.orderId} is confirmed. The restaurant will start preparing it.`);
        }
        "orders.ready" => {
            check lifecycle(topic, e.orderId, "CUSTOMER", e.customerId, "PUSH",
                string `Your order ${e.orderId} is ready and waiting for a driver.`);
        }
        "orders.cancelled" => {
            check lifecycle(topic, e.orderId, "CUSTOMER", e.customerId, "EMAIL",
                string `Your order ${e.orderId} was cancelled.`);
            check lifecycle(topic, e.orderId, "RESTAURANT", e.restaurantId, "PUSH",
                string `Order ${e.orderId} was cancelled.`);
        }
    }
}

// Customers and drivers are alerted by Delivery Service itself (notifications.send);
// here the restaurant is told what happened to its order.
function handleDelivery(string topic, DeliveryEvent e) returns error? {
    OrderIndex? idx = check lookupIndex(e.orderId);
    if topic == "delivery.assigned" {
        if idx is OrderIndex {
            check lifecycle(topic, e.orderId, "RESTAURANT", idx.restaurantId, "PUSH",
                string `Driver ${e.driverId} is collecting order ${e.orderId}.`);
        }
    } else {
        string customerId = idx is OrderIndex ? idx.customerId : "unknown";
        check lifecycle(topic, e.orderId, "CUSTOMER", customerId, "EMAIL",
            string `Your order ${e.orderId} was delivered in ${e.durationMinutes} min. Enjoy!`);
        if idx is OrderIndex {
            check lifecycle(topic, e.orderId, "RESTAURANT", idx.restaurantId, "PUSH",
                string `Order ${e.orderId} was delivered in ${e.durationMinutes} min.`);
        }
    }
}
