#!/usr/bin/env bash
# RDS writer를 EC2로 안전하게 되돌리고 정방향 복제를 재개한다.
set -Eeuo pipefail
set +x

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common-functions.sh
source "${ROOT}/common-functions.sh"

MODE="${1:-}"
RUN_ID="${2:-}"
readonly MAX_PAUSE_SECONDS="${MAX_PAUSE_SECONDS:-30}"
readonly CATCHUP_TIMEOUT_SECONDS="${CATCHUP_TIMEOUT_SECONDS:-15}"
PAUSED=0
EC2_MAY_HAVE_WRITES=0
DIRECTION_CHANGED=0

[[ "$MODE" == "check" || "$MODE" == "run" ]] \
  || die "사용법: $0 {check|run} <작업-ID>"
require_run_id "$RUN_ID"
require_root
require_commands aws diff docker flock timeout
require_healthy lookddak-postgresql
require_healthy lookddak-pgbouncer
require_healthy lookddak-pgbench
load_rds_parameters
trap cleanup_secrets EXIT

wait_slot() {
  local side="$1" slot="$2" expected="$3" actual
  for _ in $(seq 1 20); do
    if [[ "$side" == "ec2" ]]; then
      actual="$(ec2_admin_sql -Atc "SELECT COALESCE((SELECT active::text FROM pg_replication_slots WHERE slot_name='${slot}'),'missing');")"
    else
      actual="$(rds_admin_sql -Atc "SELECT COALESCE((SELECT active::text FROM pg_replication_slots WHERE slot_name='${slot}'),'missing');")"
    fi
    [[ "$actual" == "$expected" ]] && return 0
    sleep 0.5
  done
  die "slot=$slot expected=$expected actual=$actual"
}

wait_reverse_catchup() {
  local target="$1" reached
  for _ in $(seq 1 "$CATCHUP_TIMEOUT_SECONDS"); do
    reached="$(rds_admin_sql -Atc "SELECT COALESCE((SELECT confirmed_flush_lsn >= '${target}'::pg_lsn FROM pg_replication_slots WHERE slot_name='${ROLLBACK_SLOT}'),false)::text;")"
    [[ "$reached" == "true" ]] && return 0
    sleep 1
  done
  die "EC2가 RDS 목표 LSN까지 따라오지 못했습니다: $target"
}

check_preconditions() {
  [[ "$(active_pgbouncer_backend)" == "${RDS_HOST}|${RDS_PORT}|${RDS_DATABASE}||0" ]] \
    || die "PgBouncer가 PAUSE 해제된 RDS를 가리키지 않습니다"
  [[ "$(rds_admin_sql -Atc "SELECT subenabled::text FROM pg_subscription WHERE subname='${FORWARD_SUBSCRIPTION}';")" == "false" ]] \
    || die "정방향 구독은 비활성 상태여야 합니다"
  [[ "$(ec2_admin_sql -Atc "SELECT subenabled::text FROM pg_subscription WHERE subname='${ROLLBACK_SUBSCRIPTION}';")" == "true" ]] \
    || die "롤백 구독이 활성화되어 있지 않습니다"
  [[ "$(rds_admin_sql -Atc "SELECT active::text FROM pg_replication_slots WHERE slot_name='${ROLLBACK_SLOT}';")" == "true" ]] \
    || die "롤백 슬롯이 active가 아닙니다"
}

recover() {
  local rc=$?
  trap - ERR INT TERM
  set +e
  log "ROLLBACK_FAILED exit_code=$rc ec2_may_have_writes=$EC2_MAY_HAVE_WRITES"
  if [[ "$EC2_MAY_HAVE_WRITES" -eq 0 ]]; then
    if [[ "$DIRECTION_CHANGED" -eq 1 ]]; then
      rds_admin_sql -c "ALTER SUBSCRIPTION ${FORWARD_SUBSCRIPTION} DISABLE;" >/dev/null 2>&1
      ec2_admin_sql -c "ALTER SUBSCRIPTION ${ROLLBACK_SUBSCRIPTION} ENABLE;" >/dev/null 2>&1
    fi
    cp "${PGBOUNCER_DIR}/pgbouncer.rds.ini" "${PGBOUNCER_DIR}/pgbouncer.ini"
    pgbouncer_admin 'RELOAD;' >/dev/null 2>&1
    pgbouncer_admin 'RECONNECT lookddak_ai;' >/dev/null 2>&1
    [[ "$PAUSED" -eq 0 ]] || pgbouncer_admin 'RESUME lookddak_ai;' >/dev/null 2>&1
    log "FAILSAFE=RDS 경로 복구 시도 완료; 상태를 즉시 확인하세요"
  else
    [[ "$PAUSED" -eq 0 ]] || pgbouncer_admin 'RESUME lookddak_ai;' >/dev/null 2>&1
    log "FAILSAFE=EC2가 쓰기를 받았으므로 EC2 경로를 유지합니다"
  fi
  cleanup_secrets
  exit "$rc"
}

check_preconditions
if [[ "$MODE" == "check" ]]; then
  log "CHECK_COMPLETE=run 모드는 실제 writer를 EC2로 되돌립니다"
  exit 0
fi

acquire_migration_lock
start_run_log "$RUN_ID" rollback-to-ec2
trap recover ERR INT TERM

pause_start=$SECONDS
timeout --foreground 10 bash -c \
  'docker exec lookddak-pgbouncer psql -X -v ON_ERROR_STOP=1 -h /var/run/pgbouncer -p 6432 -U pgbouncer_admin -d pgbouncer -c "PAUSE lookddak_ai;"'
PAUSED=1

target_lsn="$(rds_admin_sql -Atc 'SELECT pg_current_wal_lsn();')"
wait_reverse_catchup "$target_lsn"

IFS='|' read -r seq_value seq_called <<< "$(rds_admin_sql -Atc 'SELECT last_value,is_called FROM public.products_id_seq;')"
ec2_admin_sql -Atc "SELECT setval('public.products_id_seq',${seq_value},'${seq_called}'::boolean);" >/dev/null

ec2_admin_sql -c "ALTER SUBSCRIPTION ${ROLLBACK_SUBSCRIPTION} DISABLE;" >/dev/null
DIRECTION_CHANGED=1
wait_slot rds "$ROLLBACK_SLOT" false
rds_admin_sql -c "ALTER SUBSCRIPTION ${FORWARD_SUBSCRIPTION} ENABLE;" >/dev/null
wait_slot ec2 "$FORWARD_SLOT" true

cp "${PGBOUNCER_DIR}/pgbouncer.ec2.ini" "${PGBOUNCER_DIR}/pgbouncer.ini"
pgbouncer_admin 'RELOAD;' >/dev/null
pgbouncer_admin 'RECONNECT lookddak_ai;' >/dev/null
[[ "$(active_pgbouncer_backend)" == 'postgresql|5432|lookddak_ai||1' ]] \
  || die "PgBouncer EC2 대상 설정을 확인하지 못했습니다"

elapsed="$((SECONDS - pause_start))"
((elapsed <= MAX_PAUSE_SECONDS)) || die "PAUSE 시간이 ${MAX_PAUSE_SECONDS}초를 초과했습니다: ${elapsed}s"
pgbouncer_admin 'RESUME lookddak_ai;' >/dev/null
PAUSED=0
EC2_MAY_HAVE_WRITES=1

rds_admin_sql -Atc "SELECT pg_drop_replication_slot('${ROLLBACK_SLOT}') WHERE EXISTS (SELECT 1 FROM pg_replication_slots WHERE slot_name='${ROLLBACK_SLOT}' AND NOT active);" >/dev/null
trap - ERR INT TERM
log "ROLLBACK_SUCCEEDED target_lsn=$target_lsn pause_seconds=$elapsed forward=true reverse=false"
