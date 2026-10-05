// ---- drivers ----
// status: AVAILABLE | BUSY | OFFLINE
public type Driver record {|
    string driverId;
    string name;
    string phone;
    string status;
    string createdAt;
    string updatedAt;
|};

public type NewDriver record {|
    string name;
    string phone;
|};

public type DriverStatusUpdate record {|
    string status;
|};

// ---- deliveries ----
// status: PENDING (waiting for a driver) -> ASSIGNED (out for delivery) -> COMPLETED, or CANCELLED
public type Delivery record {|
    string deliveryId;
    string orderId;
    string customerId;
    string restaurantId;
    string deliveryAddress;
    string driverId;
    string status;
    float lat;
    float lng;
    string locationUpdatedAt;
    string createdAt;
    string assignedAt;
    string completedAt;
    int durationMinutes;
|};

public type LocationUpdate record {|
    float lat;
    float lng;
|};

// ---- inbound events (extra fields are allowed) ----
type OrderReadyEvent record {
    string orderId;
    string customerId;
    string restaurantId;
    string deliveryAddress;
};

type OrderRef record {
    string orderId;
};
