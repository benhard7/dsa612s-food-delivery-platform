import ballerina/os;

configurable int port = 9003;

// docker-compose passes plain env vars (not BAL_CONFIG_VAR_*), so read them directly.
function envOr(string name, string fallback) returns string {
    string v = os:getEnv(name);
    return v == "" ? fallback : v;
}

final string KAFKA_BOOTSTRAP = envOr("KAFKA_BOOTSTRAP", "localhost:29092");
final string MONGO_URI = envOr("MONGO_URI", "mongodb://localhost:27017");
final string MONGO_DB = envOr("MONGO_DB", "payment_db");

// Simulation rule: payments above this amount are declined (lets you demo payments.failed).
final float PAYMENT_LIMIT = checkpanic float:fromString(envOr("PAYMENT_LIMIT", "5000"));
