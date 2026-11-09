# Deployment

## Docker Compose (single host / staging)
```bash
cp .env.example .env && $EDITOR .env          # set strong values
docker compose up -d --build
docker compose ps && curl -s localhost:8080/actuator/health/readiness
```
Compose is a **development** stack (dev OTP logging, sandbox payments, default ports and a published admin password). Do not expose it to other people. For anything reachable by others:
* run the backend with `SPRING_PROFILES_ACTIVE=prod` (the Docker image's default; JSON/ECS logs, OTP logging impossible). The prod profile **refuses to start** unless: the JWT secret is real (≥ 32 bytes), `JOLAY_CORS_ORIGINS` lists only `https://` origins, `JOLAY_PUBLIC_URL` is the public `https://` address, `JOLAY_ADMIN_PASSWORD` (if set) is ≥ 12 characters and not a default, payments are not the sandbox, and **one-time codes have a channel that delivers** (below);
* **OTP channel (required).** WhatsApp is the primary channel: `JOLAY_WHATSAPP_ENABLED=true`, `JOLAY_WHATSAPP_PHONE_NUMBER_ID`, `JOLAY_WHATSAPP_TOKEN`, `JOLAY_WHATSAPP_TEMPLATE` (approved utility template whose body is `{{1}}`, used for SOS alerts) and `JOLAY_WHATSAPP_OTP_TEMPLATE` (approved authentication template with a Copy code button, created through the `upsert_message_templates` API with `otp_type: COPY_CODE`). The SMS sender is the fallback for people without WhatsApp: provide a real `SmsSender` bean named `productionSmsSender`. Without one, only WhatsApp delivers codes (the backend logs a warning at start) and people without WhatsApp cannot sign up. If neither is configured the backend does not start. Undeliverable status webhooks from Meta are not handled yet: fallback happens only when Meta rejects the request synchronously;
* **Payments:** `JOLAY_PAYMENT_PROVIDER=none` (cash and wallet rides; card rides and card top-ups answer 503) or a real adapter. `sandbox` is refused in `prod` unless `JOLAY_ALLOW_SANDBOX_PAYMENTS=true` is set explicitly **and** `JOLAY_SANDBOX_WEBHOOK_SECRET` is a strong secret — that is a closed internal demo mode where any customer can mark their own card payments as paid; never use it on a deployment other people can reach, and never put the flag in a shared blueprint;
* put TLS termination + rate limiting in front (nginx/ingress), terminate `wss` at the same host;
* run **one backend instance** (see Scaling below);
* use a managed PostgreSQL with PostGIS, daily backups (`scripts/backup-db.sh`), point-in-time recovery, and test restores.

## Management port (prod)
In the `prod` profile Actuator (`/actuator/health/*`, `/actuator/prometheus`) is served on `JOLAY_MGMT_PORT` (default **8081**) and is not reachable on 8080. Do not expose 8081 through the ingress; probes and Prometheus use it. Dev/compose runs without the profile (health on 8080, metrics need a SUPER_ADMIN token).
Environment variables that must be set for `prod`: `JOLAY_JWT_SECRET`, `JOLAY_PUBLIC_URL` (public https:// address of the API), DB credentials, `JOLAY_CORS_ORIGINS` (https origins), an OTP channel (WhatsApp variables above), `JOLAY_PAYMENT_PROVIDER` (`none` or a real provider) and, for the first start, `JOLAY_ADMIN_PHONE`/`JOLAY_ADMIN_PASSWORD`. Startup is refused otherwise.

## Kubernetes
`infrastructure/kubernetes/backend.yaml` (Deployment, Service, probes, non-root, resource limits). Secrets are created with `kubectl create secret generic jolay-secrets ...` (see file header).
The manifest pins `replicas: 1` on purpose: WebSocket events, rate limits and login lockout are per instance (see Scaling below). The manifest mounts no volume for driver documents (see Driver documents).
Prometheus scrape config: `infrastructure/monitoring/prometheus.yml`; metrics at `/actuator/prometheus` (`jolay.*` counters + JVM/HTTP/Hikari).

## CI (GitHub Actions: `.github/workflows/ci.yml`)
Backend tests against a PostGIS service container, admin and partner web build+tests, Flutter analyze+test for both apps, the live contract test, backend Docker build. Release signing is checked by the manual `Android Release` workflow (`.github/workflows/android-release.yml`): it fails without the four keystore secrets, refuses to publish an APK or AAB signed with the debug key, and the apps' Gradle build refuses release tasks without `android/key.properties`. Ordinary CI does not build release artifacts, so it cannot catch a debug-signed release by itself.

## Scaling: one backend instance only
Run exactly one backend replica. Rate limiting, login lockout, promo-guess limiting and WebSocket event fan-out live in the memory of the instance; with several replicas every limit is multiplied and realtime events are silently lost for users connected elsewhere. Horizontal scaling needs shared state first (counters in PostgreSQL/Redis, an event bus) — see docs/ARCHITECTURE.md#scaling-one-backend-instance-only. Add a global rate limit at the ingress regardless.

## Driver documents
Driver IDs and licences are written to `JOLAY_DOCS_DIR` (`/data/documents` in the image) on **local disk, unencrypted and unscanned**. A container without a mounted volume loses them on every restart or deploy (Render's free plan, and the provided Kubernetes manifest, have none). This repository has no encrypted or object storage and deliberately no home-made encryption. Before accepting real documents: mount a durable, encrypted volume at that path or move storage to an encrypted object store with signed URLs and malware scanning, add backups of it, and agree retention/erasure with counsel. The prod profile logs a warning about this at every start.

## Production readiness
The Render Blueprint (`render.yaml`) is a **public pilot/staging template, not a production sign-off**. Open blockers at the time of writing (details in docs/product/STATUS.md and docs/SECURITY.md):

| Blocker | Why it matters |
|---|---|
| No durable, encrypted driver-document storage | personal data loss and exposure risk (above) |
| No real payment adapter | public deployments are cash + wallet only |
| OTP channels unverified against live Meta/SMS accounts; no SMS gateway adapter; Meta "undeliverable" webhooks not handled | people without WhatsApp may be unable to sign up |
| Single instance, in-memory limits and realtime | no horizontal scaling, no high availability |
| Release signing needs owner-provided keystore and store accounts; apps never run on a device | cannot publish |
| Legal texts, personal-data compliance for Kazakhstan, independent penetration test | cannot launch publicly |

## Maps, address search and routing: 2GIS (single provider)
Everything map-related uses **2GIS**; OpenStreetMap, Nominatim and OSRM are not used. Set one secret on the backend: **`JOLAY_2GIS_KEY`** (a key from the 2GIS Platform Manager with the Places/Suggest, Geocoder, Routing and Raster Tiles services enabled; the free demo key lasts one month and is limited to 1,000 requests per service, so production needs a purchased key). Optional: `JOLAY_2GIS_REGION_ID` if Suggest asks for a geographic restriction.

| Feature | 2GIS service | Endpoint in this backend |
|---|---|---|
| Address search | Suggest `/3.0/suggests` | `GET /api/v1/geo/places` |
| Address of a point (pickup, map picker) | `/3.0/items/geocode` | `GET /api/v1/geo/reverse` |
| Route distance / ETA, fare estimate | Routing `/routing/7.0.0/global` | used internally (`routeSource=2GIS`) |
| Navigation inside the apps (route line, ETA, manoeuvres) | Routing `/routing/7.0.0/global` (geometry + `maneuvers`) | `GET /api/v1/rides/{id}/navigation` (one routing request per ride and leg every ~12 s, shared by rider and driver; watch the quota) |
| Map tiles for all apps | Raster Tiles `tile{n}.maps.2gis.com/v2/tiles/{tileset}/{z}/{x}/{y}.png` | `GET /api/v1/geo/tiles/{z}/{x}/{y}.png` (public, cached 1 day, in-memory LRU of `jolay.maps.cache-tiles` tiles) |

The apps never see the key: the customer and driver apps and the admin/partner sites load tiles from the backend (`--dart-define=TILE_URL=...` / `VITE_TILE_URL` only override that). Tile quota is billed per tile, so keep an eye on usage; put a CDN in front of `/api/v1/geo/tiles` if traffic grows.

Behaviour without a key: address search only knows the 12 seeded Almaty landmarks, a pickup without an address is labelled with its coordinates, every route is a great-circle estimate (`routeSource=ESTIMATED`) and the tile endpoint answers 503 (blank map). With a key, any 2GIS error, timeout or malformed answer falls back to the seeded places / the estimate for that request, so ordering never stops; 3 consecutive failures pause the service for 30 s (tiles: 5 failures, 20 s). Outcomes are counted in `jolay.geocoding.twogis`, `jolay.routing.twogis` and `jolay.maps.tiles` (`outcome=ok|error|skipped|...`).

**Not yet verified against a live key:** the reverse-geocode endpoint and exact `point` shape, `region_id` behaviour, the max zoom and tile size of `online_hd`, and 2GIS terms on storing results, using raster tiles outside their SDK, and attribution (the apps show "© 2GIS"). Raster Tiles in third-party libraries (flutter_map, Leaflet) are, per the 2GIS docs, not guaranteed compatible: check with `api@2gis.com` before launch.

## Business switches to review before the pilot (all OFF / empty by default)
Nothing below spends money or changes fares until the owner configures it in the admin console.

| Switch | Where | Default | Effect |
|---|---|---|---|
| Referral programme | Admin → Settings: `referral.enabled`, `referral.referrer_bonus`, `referral.referee_bonus`, `referral.min_fare`, `referral.max_rewards_per_referrer` | `false` | When on, both sides get a wallet bonus after the invited customer's first paid ride; paid from the `PROMO` account |
| Promo codes | Admin → Promo codes | none exist | Platform-funded discount; every discount appears as a negative `PROMO` balance |
| Peak-hour windows | Admin → Pricing → Peak-hour windows | none exist | Fare multiplier by weekday and city-local time; locked per ride at request time |
| Tariff zones (surcharges) | Admin → Pricing → Tariff zones | none exist | Flat fee for trips starting/ending inside a circle (e.g. the airport); locked per ride at request time |
| Trip-link grace | Admin → Settings: `safety.share_grace_minutes` | `60` | How long a shared-trip link keeps showing the final status |
| Staff MFA enforcement | Admin → Settings: `security.staff_mfa_required` | `false` | Forces MFA enrolment for super/finance admins |

Watch the `PROMO` account (`SELECT balance FROM accounts WHERE type='PROMO'`): its negative balance is the total promo and referral spend. `SELECT sum(balance) FROM accounts` must stay 0.
The trip-sharing viewer page and the public JSON live under `/api/v1/catalog/` (no authentication); make sure the ingress forwards that prefix and that `JOLAY_PUBLIC_URL` is the public HTTPS address, because it is used to build the links sent in SMS.

## Backups & disaster recovery (plan, not exercised)
Nightly `pg_dump -Fc` shipped off-site + WAL archiving for PITR; RPO ≤ 5 min / RTO ≤ 1 h are *targets*, not verified. Money tables (`ledger_*`, `payment_*`) must be included in every backup and are append-only.
Restore drill: restore dump into a scratch DB, run `SELECT sum(balance) FROM accounts` (must be 0) and the ledger consistency queries from `IntegrationTestBase.assertLedgerBalanced`.

## Load test
Latest measurements, EXPLAIN ANALYZE results and a verified backup/restore drill: [CTO_FINAL_AUDIT.md](CTO_FINAL_AUDIT.md) §6–7. The table below is the first run (before the audit changes).
`scripts/loadtest.py`, run on the build container (4 vCPU, backend + PostgreSQL 16/PostGIS + load generator **sharing** the machine, Java 21, default Hikari pool 20), 300 seeded drivers, 150 customers, 32 client threads:

| Scenario | Result |
|---|---|
| A. driver location updates, 20 s | 32 680 requests, 100 % success, **1 633 req/s**, p50 16 ms, p95 43 ms, p99 61 ms |
| B. 150 simultaneous ride requests incl. first dispatch round | 150/150 created, p50 231 ms, p95 403 ms; 150 offers issued, **0 drivers with >1 offer** |
| C. 150 simultaneous offer accepts | 150/150 ok, p50 44 ms, p95 91 ms; 150 assigned rides, **0 drivers with >1 active ride** |
| D. 750 `GET /rides/active` polls | 100 % ok, 1 570 req/s, p95 36 ms |
| Ledger sum after run | 0.00 |

Limits of this measurement: tiny dataset (300 drivers), co-located load generator, no payment/webhook or WebSocket load, no soak test, no failure injection (DB failover, backend restart mid-ride).
Do **not** extrapolate to production capacity. Still to do: city-scale seed (≥50 k drivers), `EXPLAIN ANALYZE` of the candidate query, tuning of pool/Tomcat threads, WS fan-out load, 1–2 h soak.
