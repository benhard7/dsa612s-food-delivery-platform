import ballerina/lang.runtime;
import ballerina/log;
import ballerina/uuid;
import ballerinax/kafka;

final kafka:Producer producer = check new (KAFKA_BOOTSTRAP, {
    clientId: "payment-service",
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

function publishResult(Payment p) returns error? {
    string topic = p.status == "COMPLETED" ? "payments.completed" : "payments.failed";
    json payload = {
        orderId: p.orderId,
        paymentId: p.paymentId,
        amount: p.amount,
        status: p.status,
        reason: p.reason == "" ? () : p.reason,
        timestamp: p.updatedAt
    };
    check publish(topic, p.orderId, payload);
}

function notifyCustomer(string customerId, string orderId, string message) returns error? {
    json payload = {
        recipientType: "CUSTOMER",
        recipientId: customerId,
        channel: "EMAIL",
        message: message,
        orderId: orderId,
        timestamp: nowIso()
    };
    check publish("notifications.send", orderId, payload);
}

// orders.created -> simulate a charge -> payments.completed | payments.failed
function processPayment(OrderCreatedEvent o) returns error? {
    Payment? existing = check findByOrderId(o.orderId);
    if existing is Payment {
        log:printWarn("duplicate orders.created for " + o.orderId + ", already " + existing.status);
        return;
    }
    runtime:sleep(1); // pretend to talk to a payment gateway

    string reason = "";
    if o.total <= 0.0 {
        reason = "invalid amount";
    } else if o.total > PAYMENT_LIMIT {
        reason = "amount exceeds limit of " + PAYMENT_LIMIT.toString();
    }
    string now = nowIso();
    Payment p = {
        paymentId: "pay-" + uuid:createType1AsString(),
        orderId: o.orderId,
        customerId: o.customerId,
        amount: o.total,
        status: reason == "" ? "COMPLETED" : "FAILED",
        reason: reason,
        createdAt: now,
        updatedAt: now
    };
    check insertPayment(p);
    check publishResult(p);
    log:printInfo("payment " + p.paymentId + " for " + p.orderId + ": " + p.status);
}

// orders.cancelled -> refund if the order had been paid
function refundPayment(OrderCancelledEvent o) returns error? {
    Payment? refunded = check refundForOrder(o.orderId);
    if refunded is Payment {
        log:printInfo("refunded " + refunded.paymentId + " for " + o.orderId);
        check notifyCustomer(refunded.customerId, o.orderId, "Your payment for order " + o.orderId + " has been refunded.");
    }
}
