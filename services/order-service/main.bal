import ballerina/http;
import ballerina/log;
import ballerina/uuid;

function validate(NewOrderRequest req) returns string? {
    if req.items.length() == 0 {
        return "order must contain at least one item";
    }
    foreach OrderItem item in req.items {
        if item.qty <= 0 || item.price < 0.0 {
            return "item " + item.itemId + " has an invalid qty or price";
        }
    }
    return;
}

function createOrder(NewOrderRequest req) returns Order|error {
    float total = 0.0;
    foreach OrderItem item in req.items {
        total += <float>item.qty * item.price;
    }
    string now = nowIso();
    Order o = {
        orderId: "ord-" + uuid:createType1AsString(),
        customerId: req.customerId,
        restaurantId: req.restaurantId,
        items: req.items,
        total: total,
        deliveryAddress: req.deliveryAddress,
        status: "CREATED",
        createdAt: now,
        updatedAt: now
    };
    check insertOrder(o);
    check publishOrderCreated(o);
    return o;
}

service / on new http:Listener(port) {

    resource function get health() returns string {
        return "order-service OK";
    }

    // Place an order -> publishes orders.created
    resource function post orders(@http:Payload NewOrderRequest req)
            returns http:Created|http:BadRequest|http:InternalServerError {
        string? problem = validate(req);
        if problem is string {
            return <http:BadRequest>{body: {message: problem}};
        }
        Order|error o = createOrder(req);
        if o is error {
            log:printError("create order failed", 'error = o);
            return <http:InternalServerError>{body: {message: "could not create order"}};
        }
        return <http:Created>{body: o, headers: {"Location": "/orders/" + o.orderId}};
    }

    resource function get orders(string? customerId, string? status)
            returns Order[]|http:InternalServerError {
        Order[]|error result = listOrders(customerId, status);
        if result is error {
            log:printError("list orders failed", 'error = result);
            return <http:InternalServerError>{body: {message: "could not list orders"}};
        }
        return result;
    }

    resource function get orders/[string orderId]() returns Order|http:NotFound|http:InternalServerError {
        Order|error? o = getOrder(orderId);
        if o is error {
            log:printError("get order failed", 'error = o);
            return <http:InternalServerError>{body: {message: "could not read order"}};
        }
        if o is () {
            return <http:NotFound>{body: {message: "order not found"}};
        }
        return o;
    }

    // Full audit trail of status changes
    resource function get orders/[string orderId]/history() returns StatusChange[]|http:InternalServerError {
        StatusChange[]|error h = getHistory(orderId);
        if h is error {
            return <http:InternalServerError>{body: {message: "could not read history"}};
        }
        return h;
    }

    // Allowed until the order is OUT_FOR_DELIVERY -> publishes orders.cancelled
    resource function post orders/[string orderId]/cancel()
            returns Order|http:NotFound|http:Conflict|http:InternalServerError {
        Order|error o = moveAndPublish(orderId, "CANCELLED", "cancelled by request");
        if o is OrderNotFoundError {
            return <http:NotFound>{body: {message: o.message()}};
        }
        if o is InvalidTransitionError {
            return <http:Conflict>{body: {message: o.message()}};
        }
        if o is error {
            log:printError("cancel failed", 'error = o);
            return <http:InternalServerError>{body: {message: "could not cancel order"}};
        }
        return o;
    }
}
