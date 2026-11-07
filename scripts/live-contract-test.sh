#!/usr/bin/env bash
# Live contract test: starts the real backend against a real PostgreSQL/PostGIS database and runs the apps' real data layer against it
# (apps/customer-app/integration/live_contract_test.dart). It proves that what the server sends is what the apps parse - something the
# fake-API widget tests cannot. Does NOT need a phone, an emulator or any of the owner's accounts (SMS is read from the dev log).
#
# Requirements: JDK 21, Flutter, a PostgreSQL 16 server with PostGIS reachable with the settings below, a FRESH database
# (stale ONLINE drivers from an earlier run could receive the test orders). Set LIVE_RECREATE_DB=1 to drop+create it with local `psql`/`createdb`.
#
#   scripts/live-contract-test.sh
#
# Settings (environment): LIVE_DB_HOST=localhost LIVE_DB_PORT=5432 LIVE_DB_NAME=jolay_live LIVE_DB_USER=jolay LIVE_DB_PASSWORD=jolay
#                         LIVE_PORT=18081  LIVE_JAR=backend/build/libs/jolay-backend-0.1.0.jar (built if missing)  LIVE_RECREATE_DB=0
set -euo pipefail
cd "$(dirname "$0")/.."

DB_HOST=${LIVE_DB_HOST:-localhost}; DB_PORT=${LIVE_DB_PORT:-5432}; DB_NAME=${LIVE_DB_NAME:-jolay_live}
DB_USER=${LIVE_DB_USER:-jolay}; DB_PASSWORD=${LIVE_DB_PASSWORD:-jolay}; PORT=${LIVE_PORT:-18081}
JAR=${LIVE_JAR:-backend/build/libs/jolay-backend-0.1.0.jar}
WORK=$(mktemp -d); LOG="$WORK/backend.log"; PID=""

cleanup() { [ -n "$PID" ] && kill "$PID" 2>/dev/null || true; wait "$PID" 2>/dev/null || true; }
trap cleanup EXIT

if [ "${LIVE_RECREATE_DB:-0}" = "1" ]; then
  export PGPASSWORD="$DB_PASSWORD"
  dropdb -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" --if-exists "$DB_NAME"
  createdb -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" "$DB_NAME"
  psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -qc 'CREATE EXTENSION IF NOT EXISTS postgis'
fi

if [ ! -f "$JAR" ]; then (cd backend && ./gradlew bootJar -x test --no-daemon -q); fi

echo "Starting the backend on :$PORT (log: $LOG)"
JOLAY_DB_URL="jdbc:postgresql://$DB_HOST:$DB_PORT/$DB_NAME" JOLAY_DB_USER="$DB_USER" JOLAY_DB_PASSWORD="$DB_PASSWORD" \
JOLAY_SMS_LOG_CODE=true JOLAY_ADMIN_PHONE=+77000000000 JOLAY_ADMIN_PASSWORD=ChangeMe12345 JOLAY_CORS_ORIGINS='*' SERVER_PORT="$PORT" \
  java -jar "$JAR" > "$LOG" 2>&1 &
PID=$!

for _ in $(seq 1 90); do
  if curl -fsS "http://127.0.0.1:$PORT/actuator/health" >/dev/null 2>&1; then UP=1; break; fi
  kill -0 "$PID" 2>/dev/null || { echo "Backend exited early:"; tail -40 "$LOG"; exit 1; }
  sleep 2
done
[ "${UP:-0}" = "1" ] || { echo "Backend did not become healthy:"; tail -40 "$LOG"; exit 1; }

cd apps/customer-app
flutter pub get >/dev/null
set +e
LIVE_BACKEND_LOG="$LOG" flutter test --dart-define=JOLAY_API="http://127.0.0.1:$PORT" integration/live_contract_test.dart
CODE=$?
set -e
if [ "$CODE" -ne 0 ]; then echo "--- last backend log lines ---"; tail -40 "$LOG"; fi
exit "$CODE"
