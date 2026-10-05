import ballerina/log;
import ballerinax/kafka;

listener kafka:Listener restaurantEventListener = new (KAFKA_BOOTSTRAP, {
    groupId: "restaurant-service",
    topics: ["orders.created", "orders.confirmed", "orders.cancelled"],
    offsetReset: kafka:OFFSET_RESET_EARLIEST,
    pollingInterval: 1
});

service on restaurantEventListener {
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
            check handleOrderCreated(evt);
        }
        "orders.confirmed" => {
            OrderRef evt = check payload.cloneWithType();
            check handleOrderConfirmed(evt);
        }
        "orders.cancelled" => {
            OrderRef evt = check payload.cloneWithType();
            check handleOrderCancelled(evt);
        }
    }
}
