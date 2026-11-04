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

## Kubernetes
`infrastructure/kubernetes/backend.yaml` (Deployment, Service, probes, non-root, resource limits). Secrets are created with `kubectl create secret generic jolay-secrets ...` (see file header).
Note: WebSocket events are in-process → keep `replicas: 1` for the realtime features until events are fanned out across replicas (see ARCHITECTURE.md), or use sticky sessions and accept missed events (clients re-sync via REST).
Prometheus scrape config: `infrastructure/monitoring/prometheus.yml`; metrics at `/actuator/prometheus` (`jolay.*` counters + JVM/HTTP/Hikari).

## CI (GitHub Actions: `.github/workflows/ci.yml`)
Backend tests against a PostGIS service container, admin build+tests, Flutter analyze+test for both apps, backend Docker build. **The workflow has not been executed on GitHub yet.**

## Backups & disaster recovery (plan, not exercised)
Nightly `pg_dump -Fc` shipped off-site + WAL archiving for PITR; RPO ≤ 5 min / RTO ≤ 1 h are *targets*, not verified. Money tables (`ledger_*`, `payment_*`) must be included in every backup and are append-only.
Restore drill: restore dump into a scratch DB, run `SELECT sum(balance) FROM accounts` (must be 0) and the ledger consistency queries from `IntegrationTestBase.assertLedgerBalanced`.

## Load test
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
