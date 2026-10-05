import ballerina/log;
import ballerinax/kafka;

listener kafka:Listener deliveryEventListener = new (KAFKA_BOOTSTRAP, {
    groupId: "delivery-service",
    topics: ["orders.ready", "orders.cancelled"],
    offsetReset: kafka:OFFSET_RESET_EARLIEST,
    pollingInterval: 1
});

service on deliveryEventListener {
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
        "orders.ready" => {
            OrderReadyEvent evt = check payload.cloneWithType();
            check handleOrderReady(evt);
        }
        "orders.cancelled" => {
            OrderRef evt = check payload.cloneWithType();
            check handleOrderCancelled(evt);
        }
    }
}
