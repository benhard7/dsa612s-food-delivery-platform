import ballerina/log;
import ballerinax/kafka;

listener kafka:Listener paymentEventListener = new (KAFKA_BOOTSTRAP, {
    groupId: "payment-service",
    topics: ["orders.created", "orders.cancelled"],
    offsetReset: kafka:OFFSET_RESET_EARLIEST,
    pollingInterval: 1
});

service on paymentEventListener {
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
            OrderCreatedEvent evt = check payload.cloneWithType();
            check processPayment(evt);
        }
        "orders.cancelled" => {
            OrderCancelledEvent evt = check payload.cloneWithType();
            check refundPayment(evt);
        }
    }
}
