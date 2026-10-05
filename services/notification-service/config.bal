import ballerina/os;

configurable int port = 9005;

// docker-compose passes plain env vars (not BAL_CONFIG_VAR_*), so read them directly.
function envOr(string name, string fallback) returns string {
    string v = os:getEnv(name);
    return v == "" ? fallback : v;
}

final string KAFKA_BOOTSTRAP = envOr("KAFKA_BOOTSTRAP", "localhost:29092");
final string MONGO_URI = envOr("MONGO_URI", "mongodb://localhost:27017");
final string MONGO_DB = envOr("MONGO_DB", "notification_db");

final string[] VALID_CHANNELS = ["EMAIL", "SMS", "PUSH"];
final string[] VALID_RECIPIENTS = ["CUSTOMER", "RESTAURANT", "DRIVER"];
