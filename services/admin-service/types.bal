// ---- stored facts (one document per order / delivery, written once) ----
// Admin keeps three small collections instead of one merged "order" document, because
// orders.created, orders.cancelled and delivery.completed arrive on different topics
// with no ordering between them. Statistics are joined at query time, so the result is
// the same whichever event arrives first, and a redelivered event can never double-count.

public type OrderItem record {|
    string itemId;
    string name;
    int qty;
    float price;
|};

// collection: placed_orders
public type PlacedOrder record {|
    string orderId;
    string customerId;
    string restaurantId;
    OrderItem[] items;
    float total;
    string placedAt;
|};

// collection: cancelled_orders
public type CancelledOrder record {|
    string orderId;
    string restaurantId;
    string cancelledAt;
|};

// collection: completed_deliveries
public type CompletedDelivery record {|
    string orderId;
    string deliveryId;
    string driverId;
    int durationMinutes;
    string completedAt;
|};

// ---- inbound events (extra fields are allowed) ----
type ItemEvent record {
    string itemId = "";
    string name;
    int qty;
    float price = 0.0;
};

type OrderCreatedEvent record {
    string orderId;
    string customerId;
    string restaurantId;
    ItemEvent[] items = [];
    float total = 0.0;
    string timestamp = "";
};

type OrderCancelledEvent record {
    string orderId;
    string restaurantId = "";
    string timestamp = "";
};

type DeliveryCompletedEvent record {
    string orderId;
    string deliveryId = "";
    string driverId = "";
    int durationMinutes = 0;
    string timestamp = "";
};

// ---- statistics returned by the REST API ----
public type ItemCount record {|
    string name;
    int qty;
|};

public type RestaurantStats record {|
    string restaurantId;
    int ordersPlaced;
    int ordersCancelled;
    int ordersDelivered;
    float cancellationRate;   // cancelled / placed, 0.0 - 1.0
    float revenue;            // total value of orders that were not cancelled
    float averageOrderValue;  // revenue / non-cancelled orders
    ItemCount[] topItems;     // best sellers among non-cancelled orders (max 5)
|};

public type DriverStats record {|
    string driverId;
    int deliveries;
    float averageMinutes;
|};

public type DeliveryStats record {|
    int completed;
    float averageMinutes;
    int fastestMinutes;
    int slowestMinutes;
    DriverStats[] drivers;
|};

public type Overview record {|
    int restaurants;
    int ordersPlaced;
    int ordersCancelled;
    int ordersDelivered;
    float revenue;
    int deliveriesCompleted;
    float averageDeliveryMinutes;
|};
