# Deployment

## Docker Compose (single host / staging)
```bash
cp .env.example .env && $EDITOR .env          # set strong values
docker compose up -d --build
docker compose ps && curl -s localhost:8080/actuator/health/readiness
```
Compose is a **development** stack (dev OTP logging, default ports). For production:
* run the backend with `SPRING_PROFILES_ACTIVE=prod` (JSON/ECS logs, OTP logging impossible), `JOLAY_SMS_LOG_CODE=false`, a real `SmsSender`, and a non-sandbox payment provider;
* put TLS termination + rate limiting in front (nginx/ingress), terminate `wss` at the same host;
* use a managed PostgreSQL with PostGIS, daily backups (`scripts/backup-db.sh`), point-in-time recovery, and test restores.

## Management port (prod)
In the `prod` profile Actuator (`/actuator/health/*`, `/actuator/prometheus`) is served on `JOLAY_MGMT_PORT` (default **8081**) and is not reachable on 8080. Do not expose 8081 through the ingress; probes and Prometheus use it. Dev/compose runs without the profile (health on 8080, metrics need a SUPER_ADMIN token).
Environment variables that must be set for `prod`: `JOLAY_JWT_SECRET`, `JOLAY_PUBLIC_URL` (public https:// address of the API; startup is refused otherwise), DB credentials, `JOLAY_CORS_ORIGINS`, a real payment provider (or `JOLAY_ALLOW_SANDBOX_PAYMENTS=true` for an internal demo only).

## Kubernetes
`infrastructure/kubernetes/backend.yaml` (Deployment, Service, probes, non-root, resource limits). Secrets are created with `kubectl create secret generic jolay-secrets ...` (see file header).
Note: WebSocket events are in-process → keep `replicas: 1` for the realtime features until events are fanned out across replicas (see ARCHITECTURE.md), or use sticky sessions and accept missed events (clients re-sync via REST).
Prometheus scrape config: `infrastructure/monitoring/prometheus.yml`; metrics at `/actuator/prometheus` (`jolay.*` counters + JVM/HTTP/Hikari).

## CI (GitHub Actions: `.github/workflows/ci.yml`)
Backend tests against a PostGIS service container, admin build+tests, Flutter analyze+test for both apps, backend Docker build. First GitHub run: backend tests (PostGIS service), admin build/tests and the backend Docker build passed; the Flutter jobs failed on `flutter analyze` info-level findings, now fixed. See docs/CTO_FINAL_AUDIT.md.

## Road routing (optional, recommended before the pilot)
Without configuration every route is a great-circle estimate (`routeSource=ESTIMATED`, clients show "estimated route"). Setting `JOLAY_OSRM_URL` (for example `http://osrm:5000`) makes the backend ask an [OSRM](https://project-osrm.org) server for real road distance and duration (`routeSource=OSRM`), which makes fares and ETAs much closer to reality. OSRM is open source and runs on OpenStreetMap data, so no map licence is needed for routing (tiles and geocoding are separate questions, see STATUS.md → Mocks).

Behaviour: 2 s timeout (`jolay.routing.timeout-ms`); on any error, timeout, or "no route" the estimate is used for that request, so riders can always order; after 3 consecutive failures OSRM is skipped for 30 s (`failures-to-open`, `open-seconds`); outcomes are counted in the metric `jolay.routing.osrm{outcome=ok|no_route|error|skipped}` — alert on a rising `error`/`skipped`.

Suggested self-hosting recipe (**not exercised in this repository's CI — verify it on a staging server first**), following the OSRM project's documented Docker workflow with the Geofabrik extract for Kazakhstan:
```
wget https://download.geofabrik.de/asia/kazakhstan-latest.osm.pbf -P data/
docker run -t -v "$PWD/data:/data" ghcr.io/project-osrm/osrm-backend osrm-extract -p /opt/car.lua /data/kazakhstan-latest.osm.pbf
docker run -t -v "$PWD/data:/data" ghcr.io/project-osrm/osrm-backend osrm-partition /data/kazakhstan-latest.osrm
docker run -t -v "$PWD/data:/data" ghcr.io/project-osrm/osrm-backend osrm-customize /data/kazakhstan-latest.osrm
docker run -d -p 5000:5000 -v "$PWD/data:/data" ghcr.io/project-osrm/osrm-backend osrm-routed --algorithm mld /data/kazakhstan-latest.osrm
```
Keep the OSRM port private (only the backend needs it). Check a known pair before switching traffic: `curl "http://localhost:5000/route/v1/driving/76.9567,43.2335;76.9066,43.2025?overview=false"` must return `"code":"Ok"` with a plausible `distance` in metres. Refresh the extract periodically. Respect OpenStreetMap's attribution requirement (visible "© OpenStreetMap contributors" wherever OSM data is shown).

## Address search and reverse geocoding (optional)
Without configuration, address search only knows the 12 seeded Almaty landmarks and a pickup without an address is labelled with its coordinates. Setting `JOLAY_NOMINATIM_URL` (for example `http://nominatim:8080`) makes the backend use a [Nominatim](https://nominatim.org) server for `GET /api/v1/geo/places` and `GET /api/v1/geo/reverse` (and for the address stored on a ride when the app sends none). The UI language (`Accept-Language`: kk/ru/en) is forwarded; results are restricted to `country-codes` (default `kz`) and ranked towards the rider's position without excluding other places.

**Run your own instance.** The public nominatim.openstreetmap.org service forbids heavy use and autocomplete (see its usage policy); this adapter sends an identifying `User-Agent` (`jolay.geocoding.user-agent`) but is not meant for the public server. Nominatim needs a large PostgreSQL import of the OSM extract; a commonly used container is `mediagis/nominatim` with `PBF_URL=https://download.geofabrik.de/asia/kazakhstan-latest.osm.pbf` (**not exercised in this repository's CI — verify on staging**, including that Kazakh/Russian address quality is acceptable for your users; if it is not, a commercial geocoder behind the `ExternalGeocoder` interface is the alternative).

Behaviour: 1.5 s timeout (`jolay.geocoding.timeout-ms`); an empty answer, error, timeout or malformed body falls back to the seeded places, so the app keeps working; 3 consecutive failures skip Nominatim for 30 s; outcomes are counted in `jolay.geocoding.nominatim{outcome=ok|error|skipped}`. Keep the Nominatim port private. Show "© OpenStreetMap contributors" wherever OSM-derived data is displayed.

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
