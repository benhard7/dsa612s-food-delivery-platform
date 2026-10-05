import ballerina/log;
import ballerinax/kafka;

listener kafka:Listener adminEventListener = new (KAFKA_BOOTSTRAP, {
    groupId: "admin-service",
    topics: [
        "orders.created",
        "orders.cancelled",
        "delivery.completed"
    ],
    offsetReset: kafka:OFFSET_RESET_EARLIEST,
    pollingInterval: 1
});

service on adminEventListener {
    remote function onConsumerRecord(kafka:BytesConsumerRecord[] records) returns error? {
        foreach kafka:BytesConsumerRecord rec in records {
            string topic = rec.offset.partition.topic;
            string body = check string:fromBytes(rec.value);
            json|error parsed = body.fromJsonString();
            if parsed is error {
                log:printError("bad JSON on " + topic, 'error = parsed);
                continue;
            }
            error? result = handleEvent(topic, parsed);
            if result is error {
                log:printError("failed handling " + topic, 'error = result);
            }
        }
    }
}

function handleEvent(string topic, json payload) returns error? {
    match topic {
        "orders.created" => {
            OrderCreatedEvent e = check payload.cloneWithType();
            check handleCreated(e);
        }
        "orders.cancelled" => {
            OrderCancelledEvent e = check payload.cloneWithType();
            check handleCancelled(e);
        }
        "delivery.completed" => {
            DeliveryCompletedEvent e = check payload.cloneWithType();
            check handleDelivered(e);
        }
    }
}

function handleCreated(OrderCreatedEvent e) returns error? {
    OrderItem[] items = [];
    foreach ItemEvent i in e.items {
        OrderItem item = {itemId: i.itemId, name: i.name, qty: i.qty, price: i.price};
        items.push(item);
    }
    PlacedOrder p = {
        orderId: e.orderId,
        customerId: e.customerId,
        restaurantId: e.restaurantId,
        items: items,
        total: e.total,
        placedAt: e.timestamp == "" ? nowIso() : e.timestamp
    };
    boolean stored = check savePlaced(p);
    if !stored {
        log:printWarn("duplicate orders.created ignored: " + e.orderId);
    }
}

function handleCancelled(OrderCancelledEvent e) returns error? {
    CancelledOrder c = {
        orderId: e.orderId,
        restaurantId: e.restaurantId,
        cancelledAt: e.timestamp == "" ? nowIso() : e.timestamp
    };
    boolean stored = check saveCancelled(c);
    if !stored {
        log:printWarn("duplicate orders.cancelled ignored: " + e.orderId);
    }
}

function handleDelivered(DeliveryCompletedEvent e) returns error? {
    CompletedDelivery d = {
        orderId: e.orderId,
        deliveryId: e.deliveryId,
        driverId: e.driverId,
        durationMinutes: e.durationMinutes,
        completedAt: e.timestamp == "" ? nowIso() : e.timestamp
    };
    boolean stored = check saveDelivery(d);
    if !stored {
        log:printWarn("duplicate delivery.completed ignored: " + e.orderId);
    }
}
