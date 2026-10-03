import ballerina/http;

configurable int port = 9004;

// Placeholder so the Docker build works from day one.
// Replace/extend with the real delivery service logic.
service / on new http:Listener(port) {
    resource function get health() returns string {
        return "delivery-service OK";
    }
}
