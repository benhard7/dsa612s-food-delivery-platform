import ballerina/log;
import ballerinax/kafka;

listener kafka:Listener notificationEventListener = new (KAFKA_BOOTSTRAP, {
    groupId: "notification-service",
    topics: [
        "notifications.send",
        "orders.created",
        "payments.completed",
        "payments.failed",
        "orders.confirmed",
        "orders.ready",
        "orders.cancelled",
        "delivery.assigned",
        "delivery.completed"
    ],
    offsetReset: kafka:OFFSET_RESET_EARLIEST,
    pollingInterval: 1
});

service on notificationEventListener {
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
        "notifications.send" => {
            NotificationRequest r = check payload.cloneWithType();
            check handleDirect(r);
        }
        "orders.created" => {
            OrderEvent e = check payload.cloneWithType();
            check handleOrderCreated(e);
        }
        "payments.completed"|"payments.failed" => {
            PaymentEvent e = check payload.cloneWithType();
            check handlePayment(topic, e);
        }
        "orders.confirmed"|"orders.ready"|"orders.cancelled" => {
            OrderEvent e = check payload.cloneWithType();
            check handleOrderStatus(topic, e);
        }
        "delivery.assigned"|"delivery.completed" => {
            DeliveryEvent e = check payload.cloneWithType();
            check handleDelivery(topic, e);
        }
    }
}
