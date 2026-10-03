import ballerina/http;

configurable int port = 9005;

// Placeholder so the Docker build works from day one.
// Replace/extend with the real notification service logic.
service / on new http:Listener(port) {
    resource function get health() returns string {
        return "notification-service OK";
    }
}
