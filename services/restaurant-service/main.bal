import ballerina/http;
import ballerina/log;
import ballerina/uuid;

function serverError(string message, error e) returns http:InternalServerError {
    log:printError(message, 'error = e);
    return {body: {message: message}};
}

// Kitchen moves an order forward and tells Order Service via orders.status.updated.
function advanceKitchen(string orderId, string fromStatus, string toStatus)
        returns KitchenOrder|http:NotFound|http:Conflict|http:InternalServerError {
    KitchenOrder|error? existing = getKitchenOrder(orderId);
    if existing is error {
        return serverError("could not read kitchen order", existing);
    }
    if existing is () {
        return <http:NotFound>{body: {message: "kitchen order not found"}};
    }
    KitchenOrder|error? moved = moveKitchen(orderId, [fromStatus], toStatus, "kitchen update");
    if moved is error {
        return serverError("could not update kitchen order", moved);
    }
    if moved is () {
        return <http:Conflict>{body: {message: "order is " + existing.status + ", expected " + fromStatus}};
    }
    error? pub = publishStatusUpdate(moved.orderId, moved.restaurantId, toStatus, "");
    if pub is error {
        return serverError("order moved but event could not be published", pub);
    }
    return moved;
}

service / on new http:Listener(port) {

    resource function get health() returns string {
        return "restaurant-service OK";
    }

    // ---------- restaurants & opening hours ----------

    resource function post restaurants(@http:Payload NewRestaurant req)
            returns http:Created|http:BadRequest|http:InternalServerError {
        if !validHours(req.openTime) || !validHours(req.closeTime) {
            return <http:BadRequest>{body: {message: "openTime and closeTime must be HH:MM"}};
        }
        Restaurant r = {
            restaurantId: "rest-" + uuid:createType1AsString(),
            name: req.name,
            address: req.address,
            openTime: req.openTime,
            closeTime: req.closeTime,
            createdAt: nowIso()
        };
        error? err = insertRestaurant(r);
        if err is error {
            return serverError("could not create restaurant", err);
        }
        return <http:Created>{body: toView(r), headers: {"Location": "/restaurants/" + r.restaurantId}};
    }

    resource function get restaurants() returns RestaurantView[]|http:InternalServerError {
        Restaurant[]|error all = listRestaurants();
        if all is error {
            return serverError("could not list restaurants", all);
        }
        return from Restaurant r in all
            select toView(r);
    }

    resource function get restaurants/[string restaurantId]() returns RestaurantView|http:NotFound|http:InternalServerError {
        Restaurant|error? r = getRestaurant(restaurantId);
        if r is error {
            return serverError("could not read restaurant", r);
        }
        if r is () {
            return <http:NotFound>{body: {message: "restaurant not found"}};
        }
        return toView(r);
    }

    resource function put restaurants/[string restaurantId]/hours(@http:Payload HoursUpdate req)
            returns RestaurantView|http:NotFound|http:BadRequest|http:InternalServerError {
        if !validHours(req.openTime) || !validHours(req.closeTime) {
            return <http:BadRequest>{body: {message: "openTime and closeTime must be HH:MM"}};
        }
        boolean|error found = updateHours(restaurantId, req.openTime, req.closeTime);
        if found is error {
            return serverError("could not update hours", found);
        }
        if !found {
            return <http:NotFound>{body: {message: "restaurant not found"}};
        }
        Restaurant|error? r = getRestaurant(restaurantId);
        if r is Restaurant {
            return toView(r);
        }
        return <http:NotFound>{body: {message: "restaurant not found"}};
    }

    // ---------- menu & real-time inventory ----------

    resource function post restaurants/[string restaurantId]/menu(@http:Payload NewMenuItem req)
            returns http:Created|http:NotFound|http:BadRequest|http:Conflict|http:InternalServerError {
        if req.price < 0.0 || req.stock < 0 {
            return <http:BadRequest>{body: {message: "price and stock must not be negative"}};
        }
        Restaurant|error? r = getRestaurant(restaurantId);
        if r is error {
            return serverError("could not read restaurant", r);
        }
        if r is () {
            return <http:NotFound>{body: {message: "restaurant not found"}};
        }
        string itemId = req.itemId ?: "m-" + uuid:createType1AsString();
        MenuItem|error? existing = getMenuItem(restaurantId, itemId);
        if existing is error {
            return serverError("could not read menu", existing);
        }
        if existing is MenuItem {
            return <http:Conflict>{body: {message: "item " + itemId + " already exists"}};
        }
        MenuItem item = {itemId: itemId, restaurantId: restaurantId, name: req.name, price: req.price, stock: req.stock};
        error? err = insertMenuItem(item);
        if err is error {
            return serverError("could not add menu item", err);
        }
        return <http:Created>{body: item, headers: {"Location": "/restaurants/" + restaurantId + "/menu"}};
    }

    resource function get restaurants/[string restaurantId]/menu() returns MenuItem[]|http:InternalServerError {
        MenuItem[]|error items = listMenu(restaurantId);
        if items is error {
            return serverError("could not read menu", items);
        }
        return items;
    }

    // Manual restock / correction
    resource function put restaurants/[string restaurantId]/menu/[string itemId]/stock(@http:Payload StockUpdate req)
            returns MenuItem|http:NotFound|http:BadRequest|http:InternalServerError {
        if req.stock < 0 {
            return <http:BadRequest>{body: {message: "stock must not be negative"}};
        }
        boolean|error found = setStock(restaurantId, itemId, req.stock);
        if found is error {
            return serverError("could not update stock", found);
        }
        if !found {
            return <http:NotFound>{body: {message: "menu item not found"}};
        }
        MenuItem|error? item = getMenuItem(restaurantId, itemId);
        if item is MenuItem {
            return item;
        }
        return <http:NotFound>{body: {message: "menu item not found"}};
    }

    // ---------- kitchen ----------

    resource function get kitchen/orders(string? restaurantId, string? status)
            returns KitchenOrder[]|http:InternalServerError {
        KitchenOrder[]|error result = listKitchenOrders(restaurantId, status);
        if result is error {
            return serverError("could not list kitchen orders", result);
        }
        return result;
    }

    resource function get kitchen/orders/[string orderId]() returns KitchenOrder|http:NotFound|http:InternalServerError {
        KitchenOrder|error? k = getKitchenOrder(orderId);
        if k is error {
            return serverError("could not read kitchen order", k);
        }
        if k is () {
            return <http:NotFound>{body: {message: "kitchen order not found"}};
        }
        return k;
    }

    // CONFIRMED -> PREPARING (publishes orders.status.updated)
    resource function post kitchen/orders/[string orderId]/preparing()
            returns KitchenOrder|http:NotFound|http:Conflict|http:InternalServerError {
        return advanceKitchen(orderId, "CONFIRMED", "PREPARING");
    }

    // PREPARING -> READY (publishes orders.status.updated)
    resource function post kitchen/orders/[string orderId]/ready()
            returns KitchenOrder|http:NotFound|http:Conflict|http:InternalServerError {
        return advanceKitchen(orderId, "PREPARING", "READY");
    }
}
