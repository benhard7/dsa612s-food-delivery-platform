# Event Contract (source of truth)

**Rule:** nobody changes a topic or payload without editing this file in the same commit.
All messages are JSON. Message key = `orderId` (keeps each order's events ordered in one partition).
All topics: 3 partitions, replication factor 1. Timestamps are ISO-8601 UTC.

## Topics

| Topic | Published by | Consumed by | Trigger |
|---|---|---|---|
| `orders.created` | Order | Payment, Restaurant, Notification, Admin | Customer places order (status CREATED) |
| `payments.completed` | Payment | Order, Notification | Payment succeeded |
| `payments.failed` | Payment | Order, Notification | Payment failed -> order CANCELLED |
| `orders.confirmed` | Order | Restaurant, Notification | Payment received (status CONFIRMED) |
| `orders.status.updated` | Restaurant | Order | Kitchen sets PREPARING or READY, or REJECTED (stock/unknown restaurant) |
| `orders.ready` | Order | Delivery, Notification | Order reached READY |
| `delivery.assigned` | Delivery | Order, Notification | Driver assigned (status OUT_FOR_DELIVERY) |
| `delivery.completed` | Delivery | Order, Admin, Notification | Driver delivered (status DELIVERED) |
| `orders.cancelled` | Order | Restaurant, Payment, Notification, Admin | Order cancelled |
| `notifications.send` | any service | Notification | Direct alert request |

## Order state machine
CREATED -> CONFIRMED -> PREPARING -> READY -> OUT_FOR_DELIVERY -> DELIVERED
Any state before OUT_FOR_DELIVERY may go to CANCELLED.

| Event received by Order Service | New status |
|---|---|
| `payments.completed` | CONFIRMED (then publish `orders.confirmed`) |
| `payments.failed` | CANCELLED |
| `orders.status.updated` (PREPARING / READY) | PREPARING / READY (on READY publish `orders.ready`) |
| `orders.status.updated` (REJECTED) | CANCELLED (then publish `orders.cancelled`) |
| `delivery.assigned` | OUT_FOR_DELIVERY |
| `delivery.completed` | DELIVERED |

## Payloads

### orders.created
```json
{ "orderId": "ord-123", "customerId": "cust-45", "restaurantId": "rest-7",
  "items": [{ "itemId": "m-1", "name": "Kapana", "qty": 2, "price": 40.0 }],
  "total": 80.0, "deliveryAddress": "12 Independence Ave, Windhoek",
  "timestamp": "2026-10-03T14:30:00Z" }
```

### payments.completed / payments.failed
```json
{ "orderId": "ord-123", "paymentId": "pay-9", "amount": 80.0,
  "status": "COMPLETED", "reason": null, "timestamp": "2026-10-03T14:30:05Z" }
```

### orders.confirmed / orders.ready / orders.cancelled
```json
{ "orderId": "ord-123", "customerId": "cust-45", "restaurantId": "rest-7",
  "status": "CONFIRMED", "deliveryAddress": "12 Independence Ave, Windhoek",
  "timestamp": "2026-10-03T14:30:06Z" }
```

### orders.status.updated
```json
{ "orderId": "ord-123", "restaurantId": "rest-7", "status": "PREPARING",
  "timestamp": "2026-10-03T14:35:00Z" }
```

### delivery.assigned
```json
{ "orderId": "ord-123", "deliveryId": "del-3", "driverId": "drv-2",
  "timestamp": "2026-10-03T14:50:00Z" }
```

### delivery.completed
```json
{ "orderId": "ord-123", "deliveryId": "del-3", "driverId": "drv-2",
  "durationMinutes": 22, "timestamp": "2026-10-03T15:12:00Z" }
```

### notifications.send
```json
{ "recipientType": "CUSTOMER", "recipientId": "cust-45", "channel": "EMAIL",
  "message": "Your order is on the way", "orderId": "ord-123",
  "timestamp": "2026-10-03T14:50:01Z" }
```

## Service ports and databases

| Service | Port | MongoDB database |
|---|---|---|
| customer-service | 9000 | customer_db |
| order-service | 9001 | order_db |
| restaurant-service | 9002 | restaurant_db |
| payment-service | 9003 | payment_db |
| delivery-service | 9004 | delivery_db |
| notification-service | 9005 | notification_db |
| admin-service | 9006 | admin_db |

Kafka (from containers): `kafka:9092`. Kafka (from your laptop): `localhost:29092`.
Mongo (from containers): `mongodb://mongo:27017`. From laptop: `mongodb://localhost:27017`.

## Change log
- 2026-10-03: initial contract.
- 2026-10-03: added Dockerfile + placeholder Ballerina project per service.
- 2026-10-05: Admin also consumes `orders.created` and `orders.cancelled` (needed for restaurant statistics). No payload changes.
- 2026-10-05: Order Service implemented (REST: POST /orders, GET /orders, GET /orders/{id}, GET /orders/{id}/history, POST /orders/{id}/cancel).
- 2026-10-05: Payment Service implemented. Consumes `orders.created` and `orders.cancelled`; payments over `PAYMENT_LIMIT` (default 5000) are declined to demo `payments.failed`; cancelling a paid order marks the payment REFUNDED and sends a `notifications.send`. REST: GET /payments, GET /payments/{id}.
- 2026-10-05: Restaurant Service implemented. `orders.status.updated` may now carry `status: REJECTED` (plus optional `reason`) when stock is insufficient or the restaurant is unknown; Order Service cancels the order. REST: /restaurants, /restaurants/{id}/hours, /restaurants/{id}/menu, /kitchen/orders.
