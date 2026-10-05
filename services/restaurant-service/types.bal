// ---- restaurants & menu ----
public type Restaurant record {|
    string restaurantId;
    string name;
    string address;
    string openTime;   // "HH:MM"
    string closeTime;  // "HH:MM" (may be earlier than openTime for overnight kitchens)
    string createdAt;
|};

public type RestaurantView record {|
    *Restaurant;
    boolean openNow;
|};

public type NewRestaurant record {|
    string name;
    string address;
    string openTime = "08:00";
    string closeTime = "20:00";
|};

public type HoursUpdate record {|
    string openTime;
    string closeTime;
|};

public type MenuItem record {|
    string itemId;
    string restaurantId;
    string name;
    float price;
    int stock;
|};

public type NewMenuItem record {|
    string itemId?;
    string name;
    float price;
    int stock;
|};

public type StockUpdate record {|
    int stock;
|};

// ---- kitchen tickets ----
// status: RESERVED -> CONFIRMED -> PREPARING -> READY, or REJECTED / CANCELLED
public type OrderLine record {
    string itemId;
    string name;
    int qty;
    float price;
};

public type KitchenOrder record {|
    string orderId;
    string customerId;
    string restaurantId;
    OrderLine[] items;
    string status;
    string reason;
    string createdAt;
    string updatedAt;
|};

// ---- inbound events (extra fields are allowed) ----
type OrderCreatedEvent record {
    string orderId;
    string customerId;
    string restaurantId;
    OrderLine[] items;
};

type OrderRef record {
    string orderId;
};

type StockError distinct error;
