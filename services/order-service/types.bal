public enum OrderStatus {
    CREATED,
    CONFIRMED,
    PREPARING,
    READY,
    OUT_FOR_DELIVERY,
    DELIVERED,
    CANCELLED
}

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
    OrderStatus status;
    string createdAt;
    string updatedAt;
|};
