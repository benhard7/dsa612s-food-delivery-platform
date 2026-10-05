// ---- API / storage types ----

public type OrderItem record {|
    string itemId;
    string name;
    int qty;
    float price;
|};

public type NewOrderRequest record {|
    string customerId;
    string restaurantId;
    OrderItem[] items;
    string deliveryAddress;
|};

public type Order record {|
    string orderId;
    string customerId;
    string restaurantId;
    OrderItem[] items;
    float total;
    string deliveryAddress;
    string status;
    string createdAt;
    string updatedAt;
|};

// Audit trail: one document per state change (collection: order_events)
public type StatusChange record {|
    string orderId;
    string fromStatus;
    string toStatus;
    string reason;
    string timestamp;
|};

// Minimal shape shared by every inbound event (extra fields are allowed).
type OrderRef record {
    string orderId;
    string status?;
};

type OrderNotFoundError distinct error;
type InvalidTransitionError distinct error;
