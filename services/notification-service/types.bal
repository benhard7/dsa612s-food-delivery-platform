// status: SENT | FAILED
public type Notification record {|
    string notificationId;
    string dedupeKey;
    string recipientType;   // CUSTOMER | RESTAURANT | DRIVER
    string recipientId;
    string channel;         // EMAIL | SMS | PUSH
    string message;
    string orderId;
    string 'source;          // topic that caused it
    string status;
    string reason;
    string createdAt;
|};

// Body of notifications.send, and of POST /notifications
public type NotificationRequest record {
    string recipientType;
    string recipientId;
    string channel;
    string message;
    string orderId = "";
};

// orderId -> who ordered from where (learned from orders.created), so payment and
// delivery events, which carry no customerId, can still be addressed.
type OrderIndex record {|
    string orderId;
    string customerId;
    string restaurantId;
|};

// ---- inbound lifecycle events (extra fields are allowed) ----
type OrderEvent record {
    string orderId;
    string customerId;
    string restaurantId;
    float total = 0.0;
};

type PaymentEvent record {
    string orderId;
    float amount = 0.0;
    string? reason = ();
};

type DeliveryEvent record {
    string orderId;
    string driverId = "";
    int durationMinutes = 0;
};
