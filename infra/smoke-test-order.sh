#!/bin/bash
# Drives one order through the whole lifecycle by playing the other services' events.
# Needs: docker compose up -d kafka kafka-init mongo && order-service running on :9001
BASE="${1:-http://localhost:9001}"

pub() { # topic key json
  echo "$2|$3" | docker exec -i kafka /opt/kafka/bin/kafka-console-producer.sh \
    --bootstrap-server localhost:9092 --topic "$1" \
    --property parse.key=true --property key.separator='|' >/dev/null
}
status() { curl -s "$BASE/orders/$1" | sed -E 's/.*"status":"([A-Z_]+)".*/\1/'; }

RESP=$(curl -s -X POST "$BASE/orders" -H 'Content-Type: application/json' -d '{
  "customerId":"cust-45","restaurantId":"rest-7",
  "items":[{"itemId":"m-1","name":"Kapana","qty":2,"price":40.0}],
  "deliveryAddress":"12 Independence Ave, Windhoek"}')
ID=$(echo "$RESP" | sed -E 's/.*"orderId":"([^"]+)".*/\1/')
echo "created $ID -> $(status $ID)   (expect CREATED)"

pub payments.completed "$ID" "{\"orderId\":\"$ID\",\"paymentId\":\"pay-1\",\"amount\":80.0,\"status\":\"COMPLETED\"}"; sleep 2
echo "after payment   -> $(status $ID)   (expect CONFIRMED)"
pub orders.status.updated "$ID" "{\"orderId\":\"$ID\",\"restaurantId\":\"rest-7\",\"status\":\"PREPARING\"}"; sleep 2
echo "kitchen         -> $(status $ID)   (expect PREPARING)"
pub orders.status.updated "$ID" "{\"orderId\":\"$ID\",\"restaurantId\":\"rest-7\",\"status\":\"READY\"}"; sleep 2
echo "kitchen         -> $(status $ID)   (expect READY)"
pub delivery.assigned "$ID" "{\"orderId\":\"$ID\",\"deliveryId\":\"del-1\",\"driverId\":\"drv-2\"}"; sleep 2
echo "driver          -> $(status $ID)   (expect OUT_FOR_DELIVERY)"
pub delivery.completed "$ID" "{\"orderId\":\"$ID\",\"deliveryId\":\"del-1\",\"driverId\":\"drv-2\",\"durationMinutes\":22}"; sleep 2
echo "delivered       -> $(status $ID)   (expect DELIVERED)"
echo; echo "history:"; curl -s "$BASE/orders/$ID/history"; echo
echo "cancel after delivery (expect 409):"; curl -s -o /dev/null -w "%{http_code}\n" -X POST "$BASE/orders/$ID/cancel"
