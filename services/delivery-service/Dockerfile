# Multi-stage build for a Ballerina service
FROM ballerina/ballerina:2201.13.5 AS build
USER root
WORKDIR /app
COPY . .
RUN bal build

FROM eclipse-temurin:21-jre
WORKDIR /app
COPY --from=build /app/target/bin/*.jar app.jar
CMD ["java", "-jar", "app.jar"]
