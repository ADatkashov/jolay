# Architecture

JOLAY is a **modular monolith**: one Spring Boot deployable, one PostgreSQL/PostGIS database, packages organised by domain so that
modules can be extracted later if measurements justify it. No Redis, Kafka or microservices are used because nothing measured so far needs them.

```
Flutter customer ─┐                       ┌─ identity   (auth, JWT, OTP, refresh rotation)
Flutter driver  ──┼── REST /api/v1 + WS ──┤  customers · drivers · geography · catalog · pricing
React admin     ──┘                       │  rides (state machine) · dispatch · payments · wallet(ledger)
                                          │  support · notifications · realtime · admin · common(audit, settings)
                                          └─ PostgreSQL 16 + PostGIS (Flyway migrations)
```

## Key decisions
* **JDBC (`JdbcClient`) instead of JPA.** The hot paths are PostGIS queries, `FOR UPDATE SKIP LOCKED`, partial unique indexes and
  ledger postings where explicit SQL is clearer and safer than entity graphs. (The brief listed JPA/Hibernate as a default; this was a deliberate deviation.)
* **The database enforces invariants**, not only the application: one active ride per customer and per driver (partial unique indexes),
  one pending offer per ride and per driver, immutable ledger (triggers), non-negative customer wallets (CHECK), unique idempotency keys.
* **Server is the only source of money.** Clients send route points, category and payment method — never a fare. Final fares are
  recomputed from the recorded GPS track and elapsed time (capped at 1.5× the estimate).
* **Realtime events are hints.** They are published after the transaction commits; clients re-fetch REST state on every reconnect
  (`CONNECTED` synthetic event) and poll as a safety net. Payment/ride truth is always read from REST.
* **Pluggable boundaries:** `RouteProvider`, `PaymentProvider`, `SmsSender`, `Notifier` (push). Development implementations are clearly labelled
  and never pretend to be live (routes are flagged `ESTIMATED`, the payment gateway is `sandbox`).
* **Observability:** correlation id (`X-Request-Id`, echoed in errors and logs), Actuator health/readiness/liveness, Prometheus metrics
  (`jolay.dispatch.*`, `jolay.rides.*`, `jolay.payments.*`), ECS-format JSON logs under the `prod` profile.

## Realtime contract
`wss://host/ws?token=<access JWT>` (token in query string because browsers/mobile WS clients cannot set headers; use short-lived tokens and
redact query strings in proxy logs). Message: `{"type": "...", "data": {...}, "ts": "..."}`.
Types: `RIDE_OFFER`, `OFFER_EXPIRED`, `OFFER_CANCELLED`, `DRIVER_ACCEPTED`, `DRIVER_ARRIVING`, `DRIVER_ARRIVED`, `RIDE_STARTED`, `RIDE_COMPLETED`,
`RIDE_CANCELLED`, `RIDE_EXPIRED`, `DRIVER_CANCELLED`, `DRIVER_LOCATION_UPDATED`, `PAYMENT_STATUS_UPDATED`, `SUPPORT_MESSAGE`, `VERIFICATION_STATUS`.
Events are delivered to the connections of the addressed user only. Single-instance only: to run >1 backend replica, fan events out through
Postgres `LISTEN/NOTIFY` or a broker (not implemented).

## Maps
Routing/geocoding are interfaces. Production needs a licensed provider (Google Maps, Mapbox or 2GIS) — **none is integrated**; this requires an API
contract and credentials. Apps render tiles from `TILE_URL` (default public OSM, development only).

## Not yet built
Delivery/partner modules, fraud scoring, safety tooling beyond dialing 112, FCM, real SMS, payment-provider adapters, driver payout workflow.
Planned extension points: new modules go under `kz.jolay.<module>` with their own migrations; feature flags can live in `application_settings`.
