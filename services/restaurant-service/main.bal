import ballerina/http;

configurable int port = 9002;

// Placeholder so the Docker build works from day one.
// Replace/extend with the real restaurant service logic.
service / on new http:Listener(port) {
    resource function get health() returns string {
        return "restaurant-service OK";
    }
}
