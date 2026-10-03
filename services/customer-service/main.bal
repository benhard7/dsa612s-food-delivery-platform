import ballerina/http;

configurable int port = 9000;

// Placeholder so the Docker build works from day one.
// Replace/extend with the real customer service logic.
service / on new http:Listener(port) {
    resource function get health() returns string {
        return "customer-service OK";
    }
}
