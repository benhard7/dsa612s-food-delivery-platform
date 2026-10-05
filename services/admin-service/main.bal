import ballerina/http;
import ballerina/log;

service / on new http:Listener(port) {

    resource function get health() returns string {
        return "admin-service OK";
    }

    // GET /stats/overview - platform-wide totals
    resource function get stats/overview() returns Overview|http:InternalServerError {
        Overview|error result = computeOverview();
        if result is error {
            log:printError("overview failed", 'error = result);
            return <http:InternalServerError>{body: {message: "could not compute overview"}};
        }
        return result;
    }

    // GET /stats/restaurants - one entry per restaurant, busiest first
    resource function get stats/restaurants() returns RestaurantStats[]|http:InternalServerError {
        RestaurantStats[]|error result = computeRestaurantStats();
        if result is error {
            log:printError("restaurant stats failed", 'error = result);
            return <http:InternalServerError>{body: {message: "could not compute restaurant statistics"}};
        }
        return result;
    }

    // GET /stats/restaurants/rest-7
    resource function get stats/restaurants/[string restaurantId]()
            returns RestaurantStats|http:NotFound|http:InternalServerError {
        RestaurantStats[]|error result = computeRestaurantStats();
        if result is error {
            log:printError("restaurant stats failed", 'error = result);
            return <http:InternalServerError>{body: {message: "could not compute restaurant statistics"}};
        }
        foreach RestaurantStats s in result {
            if s.restaurantId == restaurantId {
                return s;
            }
        }
        return <http:NotFound>{body: {message: "no orders seen for restaurant " + restaurantId}};
    }

    // GET /stats/deliveries - delivery times overall and per driver
    resource function get stats/deliveries() returns DeliveryStats|http:InternalServerError {
        DeliveryStats|error result = computeDeliveryStats();
        if result is error {
            log:printError("delivery stats failed", 'error = result);
            return <http:InternalServerError>{body: {message: "could not compute delivery statistics"}};
        }
        return result;
    }
}
