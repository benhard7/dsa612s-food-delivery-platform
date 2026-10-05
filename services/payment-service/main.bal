import ballerina/http;
import ballerina/log;

service / on new http:Listener(port) {

    resource function get health() returns string {
        return "payment-service OK";
    }

    // GET /payments?orderId=ord-1&status=FAILED
    resource function get payments(string? orderId, string? status)
            returns Payment[]|http:InternalServerError {
        Payment[]|error result = listPayments(orderId, status);
        if result is error {
            log:printError("list payments failed", 'error = result);
            return <http:InternalServerError>{body: {message: "could not list payments"}};
        }
        return result;
    }

    resource function get payments/[string paymentId]() returns Payment|http:NotFound|http:InternalServerError {
        Payment|error? p = getPayment(paymentId);
        if p is error {
            log:printError("get payment failed", 'error = p);
            return <http:InternalServerError>{body: {message: "could not read payment"}};
        }
        if p is () {
            return <http:NotFound>{body: {message: "payment not found"}};
        }
        return p;
    }
}
