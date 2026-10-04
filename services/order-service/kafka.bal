import ballerinax/kafka;

const string TOPIC_ORDERS_CREATED = "orders.created";
const string TOPIC_ORDERS_CONFIRMED = "orders.confirmed";
const string TOPIC_ORDERS_READY = "orders.ready";
const string TOPIC_ORDERS_CANCELLED = "orders.cancelled";

final kafka:Producer producer = check new (kafkaBootstrap, {
    acks: kafka:ACKS_ALL,
    retryCount: 3
});

function publish(string topic, string orderId, json payload) returns error? {
    check producer->send({
        topic: topic,
        key: orderId.toBytes(),
        value: payload.toJsonString().toBytes()
    });
}
