# Distributed Food Delivery Platform (DSA612S Assignment 2)

Event-driven microservices in Ballerina, communicating via Kafka, persisting to MongoDB, orchestrated with Docker Compose.

## Services
customer, restaurant, order, payment, delivery, notification, admin (see `services/`).

## Quick start
```bash
cp .env.example .env
docker compose up -d kafka kafka-init mongo
docker compose logs kafka-init      # should list all topics
```
Run everything incl. services: `docker compose --profile services up --build`
Rebuild one service: `docker compose --profile services up --build order-service`

Develop a service locally against `localhost:29092` (Kafka) and `localhost:27017` (Mongo).

## Event contract
See [docs/events.md](docs/events.md). **Do not change topics or payloads without updating it.**

## Team workflow
- Each member owns one service folder. Branch per feature: `git checkout -b feature/<service>-<thing>`.
- Commit often with your own GitHub account (commit log counts toward marks).
- Pull before you push: `git pull --rebase origin main`.

## Architecture
_Diagram to be added in `docs/architecture.png`._

## Team
| Member | Student no. | Service(s) |
|---|---|---|
| | | |
