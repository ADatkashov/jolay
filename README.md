# JOLAY — Your City. Your Way.

Mobility · Delivery · Everyday. A Kazakhstan-born ride-hailing platform (launch city: Almaty) built as a modular
monolith with a Flutter customer app, a Flutter driver app and a React admin console.

> **Status: working foundation, not a finished product.** The taxi flow (register → request → dispatch → ride → pay → rate)
> is implemented end-to-end and covered by automated tests. Delivery, partner portal, safety tooling, fraud detection and
> real payment gateways are **not** built yet. See [docs/product/STATUS.md](docs/product/STATUS.md) for the honest list.

## Repository layout

| Path | What |
|---|---|
| `backend/` | Spring Boot 3.4 / Java 21 modular monolith, PostgreSQL + PostGIS, Flyway |
| `apps/customer-app/` | Flutter customer app (kk / ru / en) |
| `apps/driver-app/` | Flutter driver app |
| `apps/admin-web/` | React + TypeScript staff console |
| `apps/partner-web/` | React + TypeScript partner (store) portal |
| `shared/jolay_core/` | Flutter package: theme, localization, API client, auth, WebSocket client |
| `shared/design-tokens/` | Brand tokens (JSON + CSS) |
| `infrastructure/` | Kubernetes manifests, Prometheus config |
| `docs/` | Architecture, API, database, security, payments, dispatch, business rules |
| `jolay-reference.jpg` | UX reference screenshot (flow only — no assets copied) |

## Run everything locally

```bash
cp .env.example .env            # then edit secrets
docker compose up --build       # PostGIS + backend (:8080) + admin (:5173)
```
Swagger UI: http://localhost:8080/api/v1/swagger-ui · Health: http://localhost:8080/actuator/health

Admin login (dev defaults from compose): `+77000000000` / `ChangeMe12345` — **change before any shared deployment**.
In compose the OTP is written to the backend log (`JOLAY_SMS_LOG_CODE=true`, dev only): `docker compose logs backend | grep "DEV SMS"`.

Mobile apps (Android emulator reaches the host at `10.0.2.2`):
```bash
cd apps/customer-app && flutter run --dart-define=JOLAY_API=http://10.0.2.2:8080
cd apps/driver-app   && flutter run --dart-define=JOLAY_API=http://10.0.2.2:8080
```

## Tests

```bash
cd backend && ./gradlew test              # needs PostgreSQL+PostGIS (see docs/DEVELOPMENT.md)
cd apps/admin-web && npm ci && npm test
cd shared/jolay_core && flutter test
cd apps/customer-app && flutter test && flutter analyze
cd apps/driver-app && flutter test && flutter analyze
```

## Try the full ride without a phone

[docs/DEVELOPMENT.md](docs/DEVELOPMENT.md#curl-walkthrough) contains a copy-paste curl walkthrough that registers a customer and a
driver, approves the driver, requests a ride, accepts it, drives it and pays.

Audit & roadmap: [CTO_FINAL_AUDIT](docs/CTO_FINAL_AUDIT.md) · [ROADMAP 2027](docs/JOLAY_PRODUCT_ROADMAP_2027.md)

Documentation: [ARCHITECTURE](docs/ARCHITECTURE.md) · [DATABASE](docs/DATABASE.md) · [API](docs/API.md) ·
[DEVELOPMENT](docs/DEVELOPMENT.md) · [DEPLOYMENT](docs/DEPLOYMENT.md) · [SECURITY](docs/SECURITY.md) ·
[PAYMENT_INTEGRATION](docs/PAYMENT_INTEGRATION.md) · [DISPATCH_ALGORITHM](docs/DISPATCH_ALGORITHM.md) · [BUSINESS_RULES](docs/BUSINESS_RULES.md)
