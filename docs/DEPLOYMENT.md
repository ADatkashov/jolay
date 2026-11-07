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

## Business switches to review before the pilot (all OFF / empty by default)
Nothing below spends money or changes fares until the owner configures it in the admin console.

| Switch | Where | Default | Effect |
|---|---|---|---|
| Referral programme | Admin → Settings: `referral.enabled`, `referral.referrer_bonus`, `referral.referee_bonus`, `referral.min_fare`, `referral.max_rewards_per_referrer` | `false` | When on, both sides get a wallet bonus after the invited customer's first paid ride; paid from the `PROMO` account |
| Promo codes | Admin → Promo codes | none exist | Platform-funded discount; every discount appears as a negative `PROMO` balance |
| Peak-hour windows | Admin → Pricing → Peak-hour windows | none exist | Fare multiplier by weekday and city-local time; locked per ride at request time |
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
