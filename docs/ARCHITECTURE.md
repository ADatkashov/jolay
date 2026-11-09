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
  and never pretend to be live (routes are flagged `ESTIMATED`, the payment gateway is `sandbox` and exists only when selected; the OTP sender `LogSmsSender`
  delivers nothing and the prod profile refuses to start with it as the only channel).
* **Observability:** correlation id (`X-Request-Id`, echoed in errors and logs), Actuator health/readiness/liveness, Prometheus metrics
  (`jolay.dispatch.*`, `jolay.rides.*`, `jolay.payments.*`), ECS-format JSON logs under the `prod` profile.

## Realtime contract
`wss://host/ws?token=<access JWT>` (token in query string because browsers/mobile WS clients cannot set headers; use short-lived tokens and
redact query strings in proxy logs). Message: `{"type": "...", "data": {...}, "ts": "..."}`.
Types: `RIDE_OFFER`, `OFFER_EXPIRED`, `OFFER_CANCELLED`, `DRIVER_ACCEPTED`, `DRIVER_ARRIVING`, `DRIVER_ARRIVED`, `RIDE_STARTED`, `RIDE_COMPLETED`,
`RIDE_CANCELLED`, `RIDE_EXPIRED`, `DRIVER_CANCELLED`, `DRIVER_LOCATION_UPDATED`, `CUSTOMER_LOCATION_UPDATED` (driver only, while on the way to the pickup), `PAYMENT_STATUS_UPDATED`, `SUPPORT_MESSAGE`, `VERIFICATION_STATUS`.
Events are delivered to the connections of the addressed user only, **from the memory of the instance that holds the connection** (see Scaling).

## Maps
Routing/geocoding are interfaces. Production needs a licensed provider (Google Maps, Mapbox or 2GIS) — **none is integrated**; this requires an API
contract and credentials. Apps render 2GIS tiles served by the backend at `/api/v1/geo/tiles/{z}/{x}/{y}.png` (override with `TILE_URL`).

## Scaling: one backend instance only
The backend is **not horizontally scalable today**. State that lives in the memory of one instance:
* WebSocket sessions and event fan-out (`realtime`): a user connected to instance A never sees events produced on instance B;
* HTTP rate limiting (`RateLimitFilter`), login lockout (`AuthService`) and promo-guess limiting: counters are per instance, so N instances multiply every limit by N;
* the map-tile LRU cache and circuit breakers (harmless, only less efficient).
Running more than one replica therefore weakens brute-force protection and silently drops realtime events (clients fall back to REST polling/re-sync).
Before scaling out, move these to shared state (PostgreSQL tables or Redis for counters; Postgres `LISTEN/NOTIFY`, Redis pub/sub or a broker for events) and
re-measure. Until then the Kubernetes manifest pins `replicas: 1`, and a gateway/ingress rate limit is additionally required (docs/SECURITY.md).

## Not yet built
Real payment-provider adapters (only the sandbox gateway exists; public deployments run with card payments off), a real SMS gateway, verified FCM delivery,
bank payout integration, durable encrypted document storage, shared state for multi-instance operation, tariff zones as polygons, legal texts.
Delivery (Express), the partner portal and marketplace, SOS/incidents, risk flags and driver/partner payouts **are** built (docs/product/STATUS.md).
Planned extension points: new modules go under `kz.jolay.<module>` with their own migrations; feature flags can live in `application_settings`.
