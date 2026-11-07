# Development

## Prerequisites
Java 21, Node 22, Flutter 3.4x (stable), PostgreSQL 16 **with PostGIS** (or Docker). The backend tests need a database with the PostGIS extension
available and a superuser (they run `CREATE EXTENSION postgis`).

```bash
# local Postgres without Docker (Debian/Ubuntu)
sudo apt install postgresql-16 postgresql-16-postgis-3
sudo -u postgres psql -c "CREATE ROLE jolay LOGIN SUPERUSER PASSWORD 'jolay'" -c "CREATE DATABASE jolay OWNER jolay" -c "CREATE DATABASE jolay_test OWNER jolay"
cd backend && ./gradlew bootRun          # http://localhost:8080
./gradlew test                           # uses jolay_test (override: JOLAY_TEST_DB_URL/USER/PASSWORD)
```
Dev OTPs: set `JOLAY_SMS_LOG_CODE=true` and read the `[DEV SMS]` line in the log. Create the first admin with `JOLAY_ADMIN_PHONE` / `JOLAY_ADMIN_PASSWORD`.

## curl walkthrough
```bash
API=http://localhost:8080/api/v1; J='Content-Type: application/json'
# customer
curl -s $API/auth/register -H "$J" -d '{"fullName":"Aidar B","phone":"+77011112233","password":"Secret123","role":"CUSTOMER","acceptTerms":true}'
curl -s $API/auth/verify-otp -H "$J" -d '{"phone":"+77011112233","code":"<OTP from log>"}'     # -> accessToken
# driver (same, role DRIVER, phone +77012223344), then:
curl -s $API/drivers/register -H "Authorization: Bearer $DRV" -H "$J" -d '{"vehicle":{"brand":"Toyota","model":"Camry","year":2020,"color":"White","plate":"123ABC02","category":"ECONOMY"}}'
curl -s -X PUT $API/admin/drivers/<driverId>/verification -H "Authorization: Bearer $ADMIN" -H "$J" -d '{"status":"APPROVED"}'
curl -s -X PUT $API/drivers/availability -H "Authorization: Bearer $DRV" -H "$J" -d '{"online":true}'
curl -s $API/drivers/location -H "Authorization: Bearer $DRV" -H "$J" -d '{"point":{"lat":43.2340,"lng":76.9570}}'
# ride
curl -s $API/rides -H "Authorization: Bearer $CUS" -H "$J" -d '{"pickup":{"point":{"lat":43.2335,"lng":76.9567}},"dropoff":{"point":{"lat":43.2025,"lng":76.9066}},"category":"ECONOMY","paymentMethod":"CASH"}'
curl -s $API/drivers/offers -H "Authorization: Bearer $DRV"                                   # -> offer_id
curl -s -X POST $API/drivers/offers/<offer_id>/accept -H "Authorization: Bearer $DRV"
# then: /drivers/rides/{id}/en-route, (post a location at the pickup), arrived, start, (post locations), complete; customer: /rides/{id}/rating
```

## Live contract test (apps ↔ real backend)
`scripts/live-contract-test.sh` starts the real backend against a fresh PostgreSQL/PostGIS database and runs the apps' real data layer against it (`apps/customer-app/integration/live_contract_test.dart`): sign-up with the OTP read from the dev SMS log, driver onboarding and admin approval, a full ride with the WebSocket event, an Express parcel, wallet top-up, a promo + peak + zone ride, SOS, logout. It needs JDK 21, Flutter and a PostGIS server; `LIVE_RECREATE_DB=1` drops and recreates the database with the local `psql` tools. It runs in CI as the `live-contract` job. When it fails, the message names the field an app reads that the backend did not send. It deliberately lives outside `test/`, so plain `flutter test` does not run it.

## Tests
* Backend: 46 tests — unit (pricing, state machine) + integration against real PostgreSQL/PostGIS: auth/security, dispatch incl. concurrency, payments/ledger, end-to-end rides.
* `shared/jolay_core`: 9 · `customer-app`: 8 widget tests · `driver-app`: 4 · `admin-web`: 7 (vitest).
* Load test: `JOLAY_JWT_SECRET=<backend secret> python3 scripts/loadtest.py` (seeds data **and truncates users** in the target DB — use a scratch database).

## Conventions
* No string literals in widgets: add keys to `shared/jolay_core/lib/src/strings.dart` for **all three** languages (a test fails if they diverge).
* Never compute money on the client. Never trust a WebSocket event for money — re-fetch.
* Schema changes = new Flyway migration (never edit an applied one).
