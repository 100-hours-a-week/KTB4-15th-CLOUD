#!/usr/bin/env bash
set -Eeuo pipefail

readonly APP_DIR="${APP_DIR:-/srv/lookddak}"
readonly TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
readonly BACKUP_DIR="${APP_DIR}/backups/${TIMESTAMP}"

cd "$APP_DIR"
"${APP_DIR}/scripts/load-parameters.sh"
set -a
# shellcheck disable=SC1091
source .env
set +a

install -d -m 0700 "$BACKUP_DIR"
docker compose --env-file .env exec -T mysql \
  mysqldump -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" --single-transaction "$MYSQL_DATABASE" \
  > "${BACKUP_DIR}/mysql.sql"
docker compose --env-file .env exec -T postgres \
  pg_dump -U "$POSTGRES_USER" -Fc "$POSTGRES_DB" \
  > "${BACKUP_DIR}/postgres.dump"

aws s3 cp "$BACKUP_DIR" "s3://${DATABASE_BACKUP_BUCKET}/${TIMESTAMP}/" \
  --recursive --only-show-errors
echo "Uploaded database backups to s3://${DATABASE_BACKUP_BUCKET}/${TIMESTAMP}/"
