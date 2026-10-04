import ballerina/os;

configurable int port = 9001;

function envOr(string name, string fallback) returns string {
    string v = os:getEnv(name);
    return v == "" ? fallback : v;
}

final string kafkaBootstrap = envOr("KAFKA_BOOTSTRAP", "localhost:29092");
final string mongoUri = envOr("MONGO_URI", "mongodb://localhost:27017");
final string mongoDbName = envOr("MONGO_DB", "order_db");
