import ballerina/http;

configurable int port = 9001;

// Placeholder so the Docker build works from day one.
// Replace/extend with the real order service logic.
service / on new http:Listener(port) {
    resource function get health() returns string {
        return "order-service OK";
    }
}
