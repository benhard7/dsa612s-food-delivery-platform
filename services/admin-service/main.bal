import ballerina/http;

configurable int port = 9006;

// Placeholder so the Docker build works from day one.
// Replace/extend with the real admin service logic.
service / on new http:Listener(port) {
    resource function get health() returns string {
        return "admin-service OK";
    }
}
