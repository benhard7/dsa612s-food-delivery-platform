#!/bin/bash
# Creates all Kafka topics (3 partitions each). Safe to re-run.
BOOTSTRAP="${KAFKA_BOOTSTRAP:-kafka:9092}"
TOPICS=(
  orders.created
  orders.confirmed
  orders.cancelled
  orders.status.updated
  orders.ready
  payments.completed
  payments.failed
  delivery.assigned
  delivery.completed
  notifications.send
)
for t in "${TOPICS[@]}"; do
  /opt/kafka/bin/kafka-topics.sh --bootstrap-server "$BOOTSTRAP" \
    --create --if-not-exists --topic "$t" --partitions 3 --replication-factor 1
done
echo "Topics ready:"
/opt/kafka/bin/kafka-topics.sh --bootstrap-server "$BOOTSTRAP" --list
