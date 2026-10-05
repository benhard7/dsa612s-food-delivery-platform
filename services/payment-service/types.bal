// status: COMPLETED | FAILED | REFUNDED
public type Payment record {|
    string paymentId;
    string orderId;
    string customerId;
    float amount;
    string status;
    string reason;
    string createdAt;
    string updatedAt;
|};

// ---- inbound events (extra fields are allowed) ----
type OrderCreatedEvent record {
    string orderId;
    string customerId;
    float total;
};

type OrderCancelledEvent record {
    string orderId;
};
