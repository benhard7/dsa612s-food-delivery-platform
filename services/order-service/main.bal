import ballerina/http;
import ballerina/log;
import ballerina/time;
import ballerina/uuid;

service / on new http:Listener(port) {

    resource function get health() returns string {
        return "order-service OK";
    }

    resource function post orders(NewOrderRequest req)
            returns http:Created|http:BadRequest|http:InternalServerError {

        string? problem = validate(req);
        if problem is string {
            return <http:BadRequest>{body: {message: problem}};
        }

        float total = 0.0;
        foreach OrderItem item in req.items {
            total += item.price * <float>item.qty;
        }

        string now = time:utcToString(time:utcNow());
        Order newOrder = {
            orderId: "ord-" + uuid:createType4AsString(),
            customerId: req.customerId,
            restaurantId: req.restaurantId,
            items: req.items,
            total: total,
            deliveryAddress: req.deliveryAddress,
            status: CREATED,
            createdAt: now,
            updatedAt: now
        };

        error? saved = saveOrder(newOrder);
        if saved is error {
            log:printError("failed to save order", saved);
            return <http:InternalServerError>{body: {message: "could not save order"}};
        }

        json event = {
            orderId: newOrder.orderId,
            customerId: newOrder.customerId,
            restaurantId: newOrder.restaurantId,
            items: <json>newOrder.items.toJson(),
            total: newOrder.total,
            deliveryAddress: newOrder.deliveryAddress,
            timestamp: now
        };
        error? sent = publish(TOPIC_ORDERS_CREATED, newOrder.orderId, event);
        if sent is error {
            log:printError("failed to publish orders.created", sent);
            return <http:InternalServerError>{body: {message: "order saved but event not published"}};
        }

        log:printInfo("order created", orderId = newOrder.orderId);
        return <http:Created>{body: newOrder};
    }

    resource function get orders/[string orderId]()
            returns Order|http:NotFound|http:InternalServerError {
        Order|error? found = findOrder(orderId);
        if found is error {
            log:printError("lookup failed", found);
            return <http:InternalServerError>{body: {message: "lookup failed"}};
        }
        if found is () {
            return <http:NotFound>{body: {message: "order not found"}};
        }
        return found;
    }
}

function validate(NewOrderRequest req) returns string? {
    if req.customerId.trim() == "" {
        return "customerId is required";
    }
    if req.restaurantId.trim() == "" {
        return "restaurantId is required";
    }
    if req.deliveryAddress.trim() == "" {
        return "deliveryAddress is required";
    }
    if req.items.length() == 0 {
        return "at least one item is required";
    }
    foreach OrderItem item in req.items {
        if item.qty <= 0 {
            return "item qty must be greater than 0";
        }
        if item.price < 0.0 {
            return "item price cannot be negative";
        }
    }
    return ();
}
