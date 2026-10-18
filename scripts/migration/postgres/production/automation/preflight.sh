#!/usr/bin/env bash
# 운영 변경 전에 컨테이너·DB·디스크·백업·연결 상태를 읽기 전용으로 확인한다.
set -Eeuo pipefail
set +x

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common-functions.sh
source "${ROOT}/common-functions.sh"

readonly MAX_BACKUP_AGE_HOURS="${MAX_BACKUP_AGE_HOURS:-26}"
failures=0

check() {
  local label="$1"
  shift
  if "$@"; then
    log "PASS=$label"
  else
    log "FAIL=$label"
    failures=$((failures + 1))
  fi
}

check_container() {
  local name="$1"
  [[ "$(container_health "$name" 2>/dev/null || true)" == "healthy" ]]
}

check_backup() {
  local row key modified size modified_epoch now_epoch age_hours
  row="$(aws s3api list-objects-v2 \
    --region "$AWS_REGION" \
    --bucket "$BACKUP_BUCKET" \
    --prefix "${BACKUP_PREFIX}/" \
    --query 'Contents[?ends_with(Key, `.dump`)] | [-1].[Key,LastModified,Size]' \
    --output text)"

  [[ -n "$row" && "$row" != "None" ]] || return 1
  read -r key modified size <<< "$row"
  modified_epoch="$(date -d "$modified" +%s)"
  now_epoch="$(date +%s)"
  age_hours="$(( (now_epoch - modified_epoch) / 3600 ))"
  log "LATEST_BACKUP key=$key modified=$modified size_bytes=$size age_hours=$age_hours"
  ((age_hours <= MAX_BACKUP_AGE_HOURS))
}

require_root
require_commands aws date df docker grep sed

log "PREFLIGHT_STARTED utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
log "HOST=$(hostname)"
log "PRIVATE_IP=$(hostname -I | awk '{print $1}')"

df -h / /srv/lookddak/postgresql 2>/dev/null || true
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}'

for container in lookddak-postgresql lookddak-fastapi lookddak-spring lookddak-nextjs lookddak-nginx; do
  check "container_${container}_healthy" check_container "$container"
done

check "compose_base_file" test -f "${APP_DIR}/docker-compose.yaml"
check "compose_migration_overlay" test -f "$COMPOSE_OVERLAY"
check "pgbouncer_source_config" test -f "${PGBOUNCER_DIR}/pgbouncer.ec2.ini"
check "pgbouncer_rds_template" test -f "${PGBOUNCER_DIR}/pgbouncer.rds.ini.template"

log "COMPOSE_SERVICES_BEGIN"
docker compose -f "${APP_DIR}/docker-compose.yaml" config --services
log "COMPOSE_SERVICES_END"

log "POSTGRES_SETTINGS_BEGIN"
ec2_admin_sql -Atc "
  SELECT 'server_version=' || current_setting('server_version');
  SELECT 'database_size=' || pg_size_pretty(pg_database_size(current_database()));
  SELECT 'wal_level=' || current_setting('wal_level');
  SELECT 'max_replication_slots=' || current_setting('max_replication_slots');
  SELECT 'max_wal_senders=' || current_setting('max_wal_senders');
  SELECT 'max_slot_wal_keep_size=' || current_setting('max_slot_wal_keep_size');
  SELECT 'active_connections=' || count(*) FROM pg_stat_activity WHERE pid <> pg_backend_pid();
  SELECT 'long_transactions=' || count(*) FROM pg_stat_activity
   WHERE xact_start IS NOT NULL AND clock_timestamp() - xact_start > interval '10 seconds';
"
log "POSTGRES_SETTINGS_END"

log "FASTAPI_DB_TARGET_BEGIN"
docker exec lookddak-fastapi python -c \
  'import os,urllib.parse as u; x=u.urlsplit(os.environ.get("DATABASE_URL","")); print("host=%s port=%s database=%s user=%s"%(x.hostname,x.port,x.path.lstrip("/"),x.username))'
log "FASTAPI_DB_TARGET_END"

check "latest_backup_within_${MAX_BACKUP_AGE_HOURS}h" check_backup

if ((failures > 0)); then
  log "PREFLIGHT_FAILED count=$failures"
  exit 1
fi

log "PREFLIGHT_SUCCEEDED"
