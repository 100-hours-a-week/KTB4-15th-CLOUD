#!/usr/bin/env bash
# PgBouncer PAUSE 안에서 V1 PostgreSQL을 논리 복제 설정으로 재생성한다.
set -Eeuo pipefail
set +x

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common-functions.sh
source "${ROOT}/common-functions.sh"

MODE="${1:-}"
RUN_ID="${2:-}"
readonly MAX_PAUSE_SECONDS="${MAX_PAUSE_SECONDS:-30}"
readonly PAUSE_DRAIN_TIMEOUT_SECONDS="${PAUSE_DRAIN_TIMEOUT_SECONDS:-10}"
readonly POSTGRES_READY_TIMEOUT_SECONDS="${POSTGRES_READY_TIMEOUT_SECONDS:-20}"
readonly PARAMETER_LOADER="${APP_DIR}/scripts/load-parameters.sh"
PAUSED=0

usage() {
  printf '사용법: %s {check|run} <작업-ID>\n' "$(basename "$0")"
}

[[ "$MODE" == "check" || "$MODE" == "run" ]] || { usage; exit 2; }
require_run_id "$RUN_ID"
require_root
require_commands aws docker flock grep seq sleep timeout

check_preconditions() {
  test -f "$PARAMETER_LOADER" \
    || die "런타임 Parameter Store 로더가 없습니다: $PARAMETER_LOADER"
  require_healthy lookddak-postgresql
  require_healthy lookddak-pgbouncer
  require_healthy lookddak-fastapi
  grep -Eq '^COMPOSE_FILE=.*docker-compose\.postgres-migration\.yaml([:]|$)' "${APP_DIR}/.env" \
    || die "운영 마이그레이션 overlay가 활성화되어 있지 않습니다"
  [[ "$(active_pgbouncer_backend)" == 'postgresql|5432|lookddak_ai||0' ]] \
    || die "PgBouncer가 PAUSE 해제된 EC2 PostgreSQL을 가리키지 않습니다"
  docker exec lookddak-fastapi python -c '
import os, urllib.parse as u
x = u.urlsplit(os.environ.get("DATABASE_URL", ""))
raise SystemExit(0 if (x.hostname, x.port, x.username) == ("pgbouncer", 6432, "lookddak_app") else 1)
' || die "FastAPI가 PgBouncer 공통 앱 계정을 사용하지 않습니다"
  [[ "$(ec2_admin_sql -Atc "SELECT count(*) FROM pg_stat_activity WHERE xact_start IS NOT NULL AND pid <> pg_backend_pid() AND clock_timestamp()-xact_start > interval '10 seconds';")" == "0" ]] \
    || die "10초를 넘긴 트랜잭션이 있어 재시작할 수 없습니다"
  MAX_BACKUP_AGE_HOURS=26 "${ROOT}/preflight.sh" >/dev/null \
    || die "사전 점검 또는 최신 백업 검증에 실패했습니다"
  export AWS_REGION
  # shellcheck source=/dev/null
  source "$PARAMETER_LOADER"
  load_runtime_parameters
  app_compose config --quiet
}

resume_on_error() {
  local rc=$?
  trap - ERR INT TERM
  set +e
  log "RESTART_FAILED exit_code=$rc paused=$PAUSED"
  if [[ "$PAUSED" -eq 1 ]]; then
    pgbouncer_admin 'RESUME lookddak_ai;' >/dev/null 2>&1
    log "FAILSAFE=PgBouncer RESUME attempted; verify PostgreSQL and FastAPI immediately"
  fi
  declare -F cleanup_runtime_parameters >/dev/null && cleanup_runtime_parameters
  exit "$rc"
}

check_preconditions
if [[ "$MODE" == "check" ]]; then
  log "CHECK_COMPLETE=run 모드는 PgBouncer PAUSE 후 PostgreSQL을 재생성합니다"
  cleanup_runtime_parameters
  exit 0
fi

acquire_migration_lock
start_run_log "$RUN_ID" restart-postgresql-logical
trap resume_on_error ERR INT TERM

pause_started=$SECONDS
log "PAUSE_REQUESTED"
timeout --foreground "$PAUSE_DRAIN_TIMEOUT_SECONDS" bash -c \
  'docker exec lookddak-pgbouncer psql -X -v ON_ERROR_STOP=1 -h /var/run/pgbouncer -p 6432 -U pgbouncer_admin -d pgbouncer -c "PAUSE lookddak_ai;"'
PAUSED=1
[[ "$(active_pgbouncer_backend)" == 'postgresql|5432|lookddak_ai||1' ]] \
  || die "PgBouncer PAUSE 상태를 확인하지 못했습니다"

log "POSTGRESQL_RECREATE_STARTED"
app_compose up -d --no-deps --force-recreate postgresql

ready=0
for _ in $(seq 1 "$POSTGRES_READY_TIMEOUT_SECONDS"); do
  if docker exec lookddak-postgresql sh -c 'pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB"' >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 1
done
[[ "$ready" -eq 1 ]] || die "PostgreSQL이 제한 시간 안에 준비되지 않았습니다"

settings="$(ec2_admin_sql -Atc "SELECT current_setting('wal_level')||'|'||current_setting('max_replication_slots')||'|'||current_setting('max_wal_senders')||'|'||current_setting('max_slot_wal_keep_size');")"
[[ "$settings" == 'logical|10|10|2GB' ]] \
  || die "논리 복제 설정이 예상과 다릅니다: $settings"
ec2_admin_sql -Atc 'SELECT 1;' >/dev/null

elapsed="$((SECONDS - pause_started))"
((elapsed <= MAX_PAUSE_SECONDS)) || die "PAUSE 시간이 ${MAX_PAUSE_SECONDS}초를 초과했습니다: ${elapsed}s"
pgbouncer_admin 'RESUME lookddak_ai;' >/dev/null
PAUSED=0
for _ in $(seq 1 30); do
  [[ "$(container_health lookddak-postgresql 2>/dev/null || true)" == "healthy" ]] && break
  sleep 1
done
require_healthy lookddak-postgresql
require_healthy lookddak-pgbouncer

trap - ERR INT TERM
cleanup_runtime_parameters
log "RESTART_SUCCEEDED pause_seconds=$elapsed settings=$settings"
