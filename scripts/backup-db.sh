#!/usr/bin/env bash
# Daily logical backup. Schedule with cron/K8s CronJob and ship the file to off-site object storage.
set -euo pipefail
OUT="${1:-./backups}"; mkdir -p "$OUT"
PGPASSWORD="${JOLAY_DB_PASSWORD:?}" pg_dump -h "${JOLAY_DB_HOST:-localhost}" -U "${JOLAY_DB_USER:-jolay}" -Fc jolay > "$OUT/jolay-$(date +%F-%H%M).dump"
find "$OUT" -name 'jolay-*.dump' -mtime +14 -delete
