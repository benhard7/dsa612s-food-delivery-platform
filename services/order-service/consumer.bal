import ballerina/log;
import ballerinax/kafka;

listener kafka:Listener orderEventListener = new (KAFKA_BOOTSTRAP, {
    groupId: "order-service",
    topics: [
        "payments.completed",
        "payments.failed",
        "orders.status.updated",
        "delivery.assigned",
        "delivery.completed"
    ],
    offsetReset: kafka:OFFSET_RESET_EARLIEST,
    pollingInterval: 1
});

service on orderEventListener {
    remote function onConsumerRecord(kafka:BytesConsumerRecord[] records) returns error? {
        foreach kafka:BytesConsumerRecord rec in records {
            string topic = rec.offset.partition.topic;
            string body = check string:fromBytes(rec.value);
            json|error parsed = body.fromJsonString();
            if parsed is error {
                log:printError("bad JSON on " + topic, 'error = parsed);
                continue;
            }
            OrderRef|error evt = parsed.cloneWithType();
            if evt is error {
                log:printError("event on " + topic + " has no orderId", 'error = evt);
                continue;
            }
            error? result = handleEvent(topic, evt);
            if result is InvalidTransitionError || result is OrderNotFoundError {
                // duplicates / out-of-order events are expected with at-least-once delivery
                log:printWarn("ignored event on " + topic + ": " + result.message());
            } else if result is error {
                log:printError("failed handling " + topic, 'error = result);
            }
        }
    }
}

function handleEvent(string topic, OrderRef evt) returns error? {
    string id = evt.orderId;
    match topic {
        "payments.completed" => {
            _ = check moveAndPublish(id, "CONFIRMED", "payment received");
        }
        "payments.failed" => {
            _ = check moveAndPublish(id, "CANCELLED", "payment failed");
        }
        "orders.status.updated" => {
            string? status = evt?.status;
            if status == "PREPARING" || status == "READY" {
                _ = check moveAndPublish(id, <string>status, "kitchen update");
            } else if status == "REJECTED" {
                // e.g. out of stock: cancel (Payment refunds, Restaurant frees stock)
                _ = check moveAndPublish(id, "CANCELLED", "rejected by restaurant");
            } else {
                log:printWarn("orders.status.updated with unsupported status for " + id);
            }
        }
        "delivery.assigned" => {
            _ = check moveAndPublish(id, "OUT_FOR_DELIVERY", "driver assigned");
        }
        "delivery.completed" => {
            _ = check moveAndPublish(id, "DELIVERED", "delivered");
        }
    }
}
