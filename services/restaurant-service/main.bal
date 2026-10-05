import ballerina/http;
import ballerina/log;
import ballerina/uuid;

# Utility function to construct and log standard internal server errors.
#
# + message - Contextual error description to display to caller
# + e - The underlying error object for internal logging
# + return - Formatted `http:InternalServerError` HTTP response
function serverError(string message, error e) returns http:InternalServerError {
    log:printError(message, 'error = e);
    return {
        body: {message: message}
    };
}

# Advances a kitchen order status and publishes state changes via `orders.status.updated`.
#
# + orderId - Unique identifier of target order
# + fromStatus - Expected current state of the order
# + toStatus - Target state transition
# + return - Updated `KitchenOrder`, `http:NotFound`, `http:Conflict`, or `http:InternalServerError`
function advanceKitchen(string orderId, string fromStatus, string toStatus)
        returns KitchenOrder|http:NotFound|http:Conflict|http:InternalServerError {
    
    KitchenOrder|error? existing = getKitchenOrder(orderId);
    if existing is error {
        return serverError("could not read kitchen order", existing);
    }
    if existing is () {
        return {
            body: {message: "kitchen order not found"}
        };
    }

    KitchenOrder|error? moved = moveKitchen(orderId, [fromStatus], toStatus, "kitchen update");
    if moved is error {
        return serverError("could not update kitchen order", moved);
    }
    if moved is () {
        return {
            body: {message: "order is " + existing.status + ", expected " + fromStatus}
        };
    }

    error? pub = publishStatusUpdate(moved.orderId, moved.restaurantId, toStatus, "");
    if pub is error {
        return serverError("order moved but event could not be published", pub);
    }

    return moved;
}

service / on new http:Listener(port) {

    # Health probe endpoint for monitoring service status.
    #
    # + return - Status string indicator
    resource function get health() returns string {
        return "restaurant-service OK";
    }

    // =========================================================================
    // RESTAURANTS & OPENING HOURS
    // =========================================================================

    # Registers a new restaurant profile.
    #
    # + req - Payload containing name, address, and operating hours
    # + return - `http:Created` with location header, `http:BadRequest`, or `http:InternalServerError`
    resource function post restaurants(@http:Payload NewRestaurant req)
            returns http:Created|http:BadRequest|http:InternalServerError {

        if !validHours(req.openTime) || !validHours(req.closeTime) {
            return {
                body: {message: "openTime and closeTime must be HH:MM"}
            };
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

        return {
            body: toView(r), 
            headers: {"Location": "/restaurants/" + r.restaurantId}
        };
    }

    # Retrieves all registered restaurants.
    #
    # + return - List of `RestaurantView` items or `http:InternalServerError`
    resource function get restaurants() returns RestaurantView[]|http:InternalServerError {
        Restaurant[]|error all = listRestaurants();
        if all is error {
            return serverError("could not list restaurants", all);
        }

        return from Restaurant r in all
            select toView(r);
    }

    # Retrieves a single restaurant profile by ID.
    #
    # + restaurantId - Target restaurant ID
    # + return - `RestaurantView`, `http:NotFound`, or `http:InternalServerError`
    resource function get restaurants/[string restaurantId]() returns RestaurantView|http:NotFound|http:InternalServerError {
        Restaurant|error? r = getRestaurant(restaurantId);
        if r is error {
            return serverError("could not read restaurant", r);
        }
        if r is () {
            return {
                body: {message: "restaurant not found"}
            };
        }

        return toView(r);
    }

    # Updates operating hours for a given restaurant.
    #
    # + restaurantId - Target restaurant ID
    # + req - Updated open/close schedules
    # + return - Updated `RestaurantView`, `http:NotFound`, `http:BadRequest`, or `http:InternalServerError`
    resource function put restaurants/[string restaurantId]/hours(@http:Payload HoursUpdate req)
            returns RestaurantView|http:NotFound|http:BadRequest|http:InternalServerError {

        if !validHours(req.openTime) || !validHours(req.closeTime) {
            return {
                body: {message: "openTime and closeTime must be HH:MM"}
            };
        }

        boolean|error found = updateHours(restaurantId, req.openTime, req.closeTime);
        if found is error {
            return serverError("could not update hours", found);
        }
        if !found {
            return {
                body: {message: "restaurant not found"}
            };
        }

        Restaurant|error? r = getRestaurant(restaurantId);
        if r is Restaurant {
            return toView(r);
        }

        return {
            body: {message: "restaurant not found"}
        };
    }

    // =========================================================================
    // MENU & REAL-TIME INVENTORY
    // =========================================================================

    # Adds a new item to a restaurant's menu.
    #
    # + restaurantId - Target restaurant ID
    # + req - Menu item attributes including name, price, and initial stock
    # + return - `http:Created`, `http:NotFound`, `http:BadRequest`, `http:Conflict`, or `http:InternalServerError`
    resource function post restaurants/[string restaurantId]/menu(@http:Payload NewMenuItem req)
            returns http:Created|http:NotFound|http:BadRequest|http:Conflict|http:InternalServerError {

        if req.price < 0.0 || req.stock < 0 {
            return {
                body: {message: "price and stock must not be negative"}
            };
        }

        Restaurant|error? r = getRestaurant(restaurantId);
        if r is error {
            return serverError("could not read restaurant", r);
        }
        if r is () {
            return {
                body: {message: "restaurant not found"}
            };
        }

        string itemId = req.itemId ?: "m-" + uuid:createType1AsString();
        MenuItem|error? existing = getMenuItem(restaurantId, itemId);
        if existing is error {
            return serverError("could not read menu", existing);
        }
        if existing is MenuItem {
            return {
                body: {message: "item " + itemId + " already exists"}
            };
        }

        MenuItem item = {
            itemId: itemId, 
            restaurantId: restaurantId, 
            name: req.name, 
            price: req.price, 
            stock: req.stock
        };

        error? err = insertMenuItem(item);
        if err is error {
            return serverError("could not add menu item", err);
        }

        return {
            body: item, 
            headers: {"Location": "/restaurants/" + restaurantId + "/menu"}
        };
    }

    # Retrieves full menu catalog for a specific restaurant.
    #
    # + restaurantId - Target restaurant ID
    # + return - List of `MenuItem` records or `http:InternalServerError`
    resource function get restaurants/[string restaurantId]/menu() returns MenuItem[]|http:InternalServerError {
        MenuItem[]|error items = listMenu(restaurantId);
        if items is error {
            return serverError("could not read menu", items);
        }

        return items;
    }

    # Updates stock quantity for a menu item (restock/correction).
    #
    # + restaurantId - Target restaurant ID
    # + itemId - Target item ID
    # + req - Stock update payload
    # + return - Updated `MenuItem`, `http:NotFound`, `http:BadRequest`, or `http:InternalServerError`
    resource function put restaurants/[string restaurantId]/menu/[string itemId]/stock(@http:Payload StockUpdate req)
            returns MenuItem|http:NotFound|http:BadRequest|http:InternalServerError {

        if req.stock < 0 {
            return {
                body: {message: "stock must not be negative"}
            };
        }

        boolean|error found = setStock(restaurantId, itemId, req.stock);
        if found is error {
            return serverError("could not update stock", found);
        }
        if !found {
            return {
                body: {message: "menu item not found"}
            };
        }

        MenuItem|error? item = getMenuItem(restaurantId, itemId);
        if item is MenuItem {
            return item;
        }

        return {
            body: {message: "menu item not found"}
        };
    }

    // =========================================================================
    // KITCHEN MANAGEMENT
    // =========================================================================

    # Queries kitchen orders filtered by restaurant and status.
    #
    # + restaurantId - Optional restaurant filter
    # + status - Optional status filter
    # + return - List of `KitchenOrder` records or `http:InternalServerError`
    resource function get kitchen/orders(string? restaurantId, string? status)
            returns KitchenOrder[]|http:InternalServerError {

        KitchenOrder[]|error result = listKitchenOrders(restaurantId, status);
        if result is error {
            return serverError("could not list kitchen orders", result);
        }

        return result;
    }

    # Retrieves single kitchen order details by order ID.
    #
    # + orderId - Target order ID
    # + return - `KitchenOrder`, `http:NotFound`, or `http:InternalServerError`
    resource function get kitchen/orders/[string orderId]() returns KitchenOrder|http:NotFound|http:InternalServerError {
        KitchenOrder|error? k = getKitchenOrder(orderId);
        if k is error {
            return serverError("could not read kitchen order", k);
        }
        if k is () {
            return {
                body: {message: "kitchen order not found"}
            };
        }

        return k;
    }

    # Transitions order status from CONFIRMED -> PREPARING and emits `orders.status.updated`.
    #
    # + orderId - Target order ID
    # + return - Updated `KitchenOrder`, `http:NotFound`, `http:Conflict`, or `http:InternalServerError`
    resource function post kitchen/orders/[string orderId]/preparing()
            returns KitchenOrder|http:NotFound|http:Conflict|http:InternalServerError {
        return advanceKitchen(orderId, "CONFIRMED", "PREPARING");
    }

    # Transitions order status from PREPARING -> READY and emits `orders.status.updated`.
    #
    # + orderId - Target order ID
    # + return - Updated `KitchenOrder`, `http:NotFound`, `http:Conflict`, or `http:InternalServerError`
    resource function post kitchen/orders/[string orderId]/ready()
            returns KitchenOrder|http:NotFound|http:Conflict|http:InternalServerError {
        return advanceKitchen(orderId, "PREPARING", "READY");
    }
}
