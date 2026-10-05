import ballerina/http;
import ballerina/log;

# Utility function to construct and log standard internal server errors.
#
# + message - Contextual error description to display to caller
# + e - The underlying error object for internal logging
# + return - Formatted `http:InternalServerError` HTTP response
function serverError(string message, error e) returns http:InternalServerError {
    log:printError(message, 'error = e);
    return <http:internalservererror>{
        body: {message: message}
    };
}

service / on new http:Listener(port) {

    # Basic health probe endpoint for container orchestrators.
    #
    # + return - Status indicator string
    resource function get health() returns string {
        return "notification-service OK";
    }

    # Requests an immediate notification alert.
    # 
    # Dispatches the payload through Kafka (`notifications.send`) following standard inter-service patterns.
    #
    # + req - The request payload containing recipient, channel, and message details
    # + return - `http:Accepted` if successfully queued, `http:BadRequest` on validation failure, 
    #            or `http:InternalServerError` on publishing failure
    resource function post notifications(@http:Payload NotificationRequest req)
            returns http:Accepted|http:BadRequest|http:InternalServerError {

        // Validate recipient type against permitted constant values
        if VALID_RECIPIENTS.indexOf(req.recipientType) is () {
            return <http:badrequest>{
                body: {message: "recipientType must be CUSTOMER, RESTAURANT or DRIVER"}
            };
        }

        // Validate notification delivery channel
        if VALID_CHANNELS.indexOf(req.channel) is () {
            return <http:badrequest>{
                body: {message: "channel must be EMAIL, SMS or PUSH"}
            };
        }

        // Ensure required fields are non-empty strings
        if req.recipientId.trim() == "" || req.message.trim() == "" {
            return <http:badrequest>{
                body: {message: "recipientId and message are required"}
            };
        }

        // Construct notification event structure for downstream streaming
        json payload = {
            recipientType: req.recipientType,
            recipientId: req.recipientId,
            channel: req.channel,
            message: req.message,
            orderId: req.orderId,
            timestamp: nowIso()
        };

        // Publish message event to notification stream topic
        error? err = publish("notifications.send", req.orderId, payload);
        if err is error {
            return serverError("could not queue notification", err);
        }

        return <http:accepted>{
            body: {message: "queued"}
        };
    }

    # Query notifications by filtering attributes.
    #
    # + orderId - Optional order identifier filter
    # + recipientId - Optional target recipient identifier
    # + recipientType - Optional entity category filter
    # + channel - Optional messaging channel filter
    # + status - Optional delivery status filter
    # + return - List of matching `Notification` records or `http:InternalServerError`
    resource function get notifications(string? orderId, string? recipientId, string? recipientType,
            string? channel, string? status) returns Notification[]|http:InternalServerError {

        Notification[]|error result = listNotifications(orderId, recipientId, recipientType, channel, status);
        if result is error {
            return serverError("could not list notifications", result);
        }

        return result;
    }

    # Retrieve a specific notification record by ID.
    #
    # + notificationId - Unique identifier of target notification
    # + return - Matching `Notification`, `http:NotFound` if missing, or `http:InternalServerError`
    resource function get notifications/[string notificationId]()
            returns Notification|http:NotFound|http:InternalServerError {

        Notification|error? n = getNotification(notificationId);
        if n is error {
            return serverError("could not read notification", n);
        }

        if n is () {
            return <http:notfound>{
                body: {message: "notification not found"}
            };
        }

        return n;
    }
}
