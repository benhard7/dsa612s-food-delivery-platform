import ballerina/http; 
 
type Customer record {| 
    string customerId; 
    string name; 
    string email; 
    string phone; 
    string[] addresses = []; 
    string[] orderHistory = []; 
|}; 
 
type AddressRequest record {| 
    string address; 
|}; 
 
map<Customer> customerStore = {}; 
 
service / on new http:Listener(8080) { 
 
     
    resource function post customers(@http:Payload Customer newCustomer)
        returns http:Response|error {

    http:Response response = new;

    if (customerStore[newCustomer.customerId] is Customer) {
        response.statusCode = 409;
        response.setJsonPayload({
            message: "A customer with this ID already exists."
        });
        return response;
    }

    customerStore[newCustomer.customerId] = newCustomer;

    response.statusCode = 201;
    response.setJsonPayload(newCustomer);
    return response;
}
 
        resource function get customers() returns http:Response|error {
    http:Response response = new;
    Customer[] customers = [];

    foreach Customer customer in customerStore {
        customers.push(customer);
    }

    response.setJsonPayload(customers);
    return response;
}
 
     
  resource function get customers/[string customerId]() returns http:Response|error {
    http:Response response = new;

    Customer? customer = customerStore[customerId];

    if customer is () {
        response.statusCode = 404;
        response.setJsonPayload({
            message: "Customer not found."
        });
        return response;
    }

    response.setJsonPayload(customer);
    return response;
}
     
   resource function put customers/[string customerId](
        @http:Payload Customer updatedCustomer) returns http:Response|error {

    http:Response response = new;

    if !(customerStore[customerId] is Customer) {
        response.statusCode = 404;
        response.setJsonPayload({
            message: "Customer not found."
        });
        return response;
    }

    if updatedCustomer.customerId != customerId {
        response.statusCode = 400;
        response.setJsonPayload({
            message: "The customerId in the body must match the URL."
        });
        return response;
    }

    customerStore[customerId] = updatedCustomer;

    response.setJsonPayload(updatedCustomer);
    return response;
}
 
 
        resource function delete customers/[string customerId]() returns http:Response|error {
    http:Response response = new;

    if !(customerStore[customerId] is Customer) {
        response.statusCode = 404;
        response.setJsonPayload({
            message: "Customer not found."
        });
        return response;
    }

    _ = customerStore.remove(customerId);
    response.statusCode = 200;
    response.setJsonPayload({
        message: "Customer deleted successfully."
    });
    return response;
}
 
 
       resource function post customers/[string customerId]/addresses(
        @http:Payload AddressRequest addressRequest) returns http:Response|error {

    http:Response response = new;

    Customer? customer = customerStore[customerId];

    if customer is () {
        response.statusCode = 404;
        response.setJsonPayload({
            message: "Customer not found."
        });
        return response;
    }

    customer.addresses.push(addressRequest.address);
    customerStore[customerId] = customer;

    response.statusCode = 201;
    response.setJsonPayload(customer);
    return response;
}
    resource function get customers/[string customerId]/orders() returns http:Response|error {
    http:Response response = new;

    Customer? customer = customerStore[customerId];

    if customer is () {
        response.statusCode = 404;
        response.setJsonPayload({
            message: "Customer not found."
        });
        return response;
    }

    response.setJsonPayload(customer.orderHistory);
    return response;
    }  
    
    
    }