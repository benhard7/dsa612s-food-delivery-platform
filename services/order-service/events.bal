import ballerinax/kafka;

final kafka:Producer producer = check new (KAFKA_BOOTSTRAP, {
    clientId: "order-service",
    acks: "all",
    retryCount: 3
});

// Statuses that Order Service announces on Kafka
final map<string> STATUS_TOPIC = {
    "CONFIRMED": "orders.confirmed",
    "READY": "orders.ready",
    "CANCELLED": "orders.cancelled"
};

// Key = orderId so all events of one order land in the same partition (ordered).
function publish(string topic, string orderId, json payload) returns error? {
    check producer->send({
        topic: topic,
        key: orderId.toBytes(),
        value: payload.toJsonString().toBytes()
    });
}

function publishOrderCreated(Order o) returns error? {
    json payload = {
        orderId: o.orderId,
        customerId: o.customerId,
        restaurantId: o.restaurantId,
        items: o.items.toJson(),
        total: o.total,
        deliveryAddress: o.deliveryAddress,
        timestamp: o.createdAt
    };
    check publish("orders.created", o.orderId, payload);
}

function publishStatus(Order o) returns error? {
    string? topic = STATUS_TOPIC[o.status];
    if topic is () {
        return; // PREPARING / OUT_FOR_DELIVERY / DELIVERED are not announced by Order Service
    }
    json payload = {
        orderId: o.orderId,
        customerId: o.customerId,
        restaurantId: o.restaurantId,
        status: o.status,
        deliveryAddress: o.deliveryAddress,
        timestamp: o.updatedAt
    };
    check publish(topic, o.orderId, payload);
}

// Transition + publish. Used by both the REST API (cancel) and the Kafka consumers.
function moveAndPublish(string orderId, string toStatus, string reason) returns Order|error {
    Order o = check applyTransition(orderId, toStatus, reason);
    check publishStatus(o);
    return o;
}
