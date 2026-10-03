import ballerina/http;

configurable int port = 9003;

// Placeholder so the Docker build works from day one.
// Replace/extend with the real payment service logic.
service / on new http:Listener(port) {
    resource function get health() returns string {
        return "payment-service OK";
    }
}
