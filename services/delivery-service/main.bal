import ballerina/http;
import ballerina/log;
import ballerina/uuid;

function serverError(string message, error e) returns http:InternalServerError {
    log:printError(message, 'error = e);
    return {body: {message: message}};
}

// Driver confirms the drop-off: ASSIGNED -> COMPLETED, driver is freed, delivery.completed is published.
function finishDelivery(string deliveryId) returns Delivery|http:NotFound|http:Conflict|http:InternalServerError {
    Delivery|error? d = getDelivery(deliveryId);
    if d is error {
        return serverError("could not read delivery", d);
    }
    if d is () {
        return <http:NotFound>{body: {message: "delivery not found"}};
    }
    if d.status != "ASSIGNED" {
        return <http:Conflict>{body: {message: "delivery is " + d.status + ", only ASSIGNED deliveries can be completed"}};
    }
    boolean|error done = completeDelivery(deliveryId, minutesSince(d.assignedAt));
    if done is error {
        return serverError("could not complete delivery", done);
    }
    if !done {
        return <http:Conflict>{body: {message: "delivery changed state, please retry"}};
    }
    error? freed = freeDriver(d.driverId);
    if freed is error {
        log:printError("could not free driver " + d.driverId, 'error = freed);
    }
    Delivery|error? updated = getDelivery(deliveryId);
    if updated is error {
        return serverError("could not read delivery", updated);
    }
    if updated is () {
        return <http:NotFound>{body: {message: "delivery not found"}};
    }
    error? pub = publishCompleted(updated);
    if pub is error {
        return serverError("delivery completed but event could not be published", pub);
    }
    error? next = assignPending(); // this driver may now take a waiting delivery
    if next is error {
        log:printError("assigning pending deliveries failed", 'error = next);
    }
    return updated;
}

service / on new http:Listener(port) {

    resource function get health() returns string {
        return "delivery-service OK";
    }

    // ---------- drivers ----------

    resource function post drivers(@http:Payload NewDriver req)
            returns http:Created|http:BadRequest|http:InternalServerError {
        if req.name.trim() == "" {
            return <http:BadRequest>{body: {message: "name is required"}};
        }
        string now = nowIso();
        Driver d = {
            driverId: "drv-" + uuid:createType1AsString(),
            name: req.name,
            phone: req.phone,
            status: "AVAILABLE",
            createdAt: now,
            updatedAt: now
        };
        error? err = insertDriver(d);
        if err is error {
            return serverError("could not register driver", err);
        }
        error? next = assignPending(); // a new driver may unblock waiting deliveries
        if next is error {
            log:printError("assigning pending deliveries failed", 'error = next);
        }
        return <http:Created>{body: d, headers: {"Location": "/drivers/" + d.driverId}};
    }

    resource function get drivers(string? status) returns Driver[]|http:InternalServerError {
        Driver[]|error all = listDrivers(status);
        if all is error {
            return serverError("could not list drivers", all);
        }
        return all;
    }

    resource function get drivers/[string driverId]() returns Driver|http:NotFound|http:InternalServerError {
        Driver|error? d = getDriver(driverId);
        if d is error {
            return serverError("could not read driver", d);
        }
        if d is () {
            return <http:NotFound>{body: {message: "driver not found"}};
        }
        return d;
    }

    // Go on/off shift. Only AVAILABLE and OFFLINE can be set by hand; BUSY is managed by assignments.
    resource function put drivers/[string driverId]/status(@http:Payload DriverStatusUpdate req)
            returns Driver|http:NotFound|http:BadRequest|http:Conflict|http:InternalServerError {
        if req.status != "AVAILABLE" && req.status != "OFFLINE" {
            return <http:BadRequest>{body: {message: "status must be AVAILABLE or OFFLINE"}};
        }
        Driver|error? current = getDriver(driverId);
        if current is error {
            return serverError("could not read driver", current);
        }
        if current is () {
            return <http:NotFound>{body: {message: "driver not found"}};
        }
        if current.status == "BUSY" {
            return <http:Conflict>{body: {message: "driver is on a delivery and cannot change status"}};
        }
        boolean|error ok = setDriverStatus(driverId, req.status);
        if ok is error {
            return serverError("could not update driver", ok);
        }
        if req.status == "AVAILABLE" {
            error? next = assignPending();
            if next is error {
                log:printError("assigning pending deliveries failed", 'error = next);
            }
        }
        Driver|error? updated = getDriver(driverId);
        if updated is Driver {
            return updated;
        }
        return <http:NotFound>{body: {message: "driver not found"}};
    }

    // ---------- deliveries ----------

    resource function get deliveries(string? orderId, string? status, string? driverId)
            returns Delivery[]|http:InternalServerError {
        Delivery[]|error result = listDeliveries(orderId, status, driverId);
        if result is error {
            return serverError("could not list deliveries", result);
        }
        return result;
    }

    resource function get deliveries/[string deliveryId]() returns Delivery|http:NotFound|http:InternalServerError {
        Delivery|error? d = getDelivery(deliveryId);
        if d is error {
            return serverError("could not read delivery", d);
        }
        if d is () {
            return <http:NotFound>{body: {message: "delivery not found"}};
        }
        return d;
    }

    // Driver app reports the drop-off -> publishes delivery.completed
    resource function post deliveries/[string deliveryId]/complete()
            returns Delivery|http:NotFound|http:Conflict|http:InternalServerError {
        return finishDelivery(deliveryId);
    }

    // Live position of the driver (only while the delivery is ASSIGNED)
    resource function put deliveries/[string deliveryId]/location(@http:Payload LocationUpdate req)
            returns Delivery|http:NotFound|http:Conflict|http:InternalServerError {
        Delivery|error? d = getDelivery(deliveryId);
        if d is error {
            return serverError("could not read delivery", d);
        }
        if d is () {
            return <http:NotFound>{body: {message: "delivery not found"}};
        }
        boolean|error ok = updateLocation(deliveryId, req.lat, req.lng);
        if ok is error {
            return serverError("could not update location", ok);
        }
        if !ok {
            return <http:Conflict>{body: {message: "delivery is " + d.status + ", location can only be updated while ASSIGNED"}};
        }
        Delivery|error? updated = getDelivery(deliveryId);
        if updated is Delivery {
            return updated;
        }
        return <http:NotFound>{body: {message: "delivery not found"}};
    }
}
