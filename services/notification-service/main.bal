import ballerina/http;
import ballerina/log;

function serverError(string message, error e) returns http:InternalServerError {
    log:printError(message, 'error = e);
    return {body: {message: message}};
}

service / on new http:Listener(port) {

    resource function get health() returns string {
        return "notification-service OK";
    }

    // Ask for an alert directly. It goes through Kafka (notifications.send) like any other service's request.
    resource function post notifications(@http:Payload NotificationRequest req)
            returns http:Accepted|http:BadRequest|http:InternalServerError {
        if VALID_RECIPIENTS.indexOf(req.recipientType) is () {
            return <http:BadRequest>{body: {message: "recipientType must be CUSTOMER, RESTAURANT or DRIVER"}};
        }
        if VALID_CHANNELS.indexOf(req.channel) is () {
            return <http:BadRequest>{body: {message: "channel must be EMAIL, SMS or PUSH"}};
        }
        if req.recipientId.trim() == "" || req.message.trim() == "" {
            return <http:BadRequest>{body: {message: "recipientId and message are required"}};
        }
        json payload = {
            recipientType: req.recipientType,
            recipientId: req.recipientId,
            channel: req.channel,
            message: req.message,
            orderId: req.orderId,
            timestamp: nowIso()
        };
        error? err = publish("notifications.send", req.orderId, payload);
        if err is error {
            return serverError("could not queue notification", err);
        }
        return <http:Accepted>{body: {message: "queued"}};
    }

    // GET /notifications?orderId=&recipientId=&recipientType=&channel=&status=
    resource function get notifications(string? orderId, string? recipientId, string? recipientType,
            string? channel, string? status) returns Notification[]|http:InternalServerError {
        Notification[]|error result = listNotifications(orderId, recipientId, recipientType, channel, status);
        if result is error {
            return serverError("could not list notifications", result);
        }
        return result;
    }

    resource function get notifications/[string notificationId]()
            returns Notification|http:NotFound|http:InternalServerError {
        Notification|error? n = getNotification(notificationId);
        if n is error {
            return serverError("could not read notification", n);
        }
        if n is () {
            return <http:NotFound>{body: {message: "notification not found"}};
        }
        return n;
    }
}
