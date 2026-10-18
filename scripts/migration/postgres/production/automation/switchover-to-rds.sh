#!/usr/bin/env bash
# EC2 -> RDS 전환을 최대 30초 PAUSE 안에서 수행한다.
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
RDS_MAY_HAVE_WRITES=0
DIRECTION_CHANGED=0

[[ "$MODE" == "check" || "$MODE" == "run" ]] \
  || die "사용법: $0 {check|run} <작업-ID>"
require_run_id "$RUN_ID"
require_root
require_commands aws diff docker flock grep timeout
require_healthy lookddak-postgresql
require_healthy lookddak-pgbouncer
require_healthy lookddak-pgbench
require_healthy lookddak-fastapi
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

wait_forward_catchup() {
  local target="$1" reached
  for _ in $(seq 1 "$CATCHUP_TIMEOUT_SECONDS"); do
    reached="$(ec2_admin_sql -Atc "SELECT COALESCE((SELECT confirmed_flush_lsn >= '${target}'::pg_lsn FROM pg_replication_slots WHERE slot_name='${FORWARD_SLOT}'),false)::text;")"
    [[ "$reached" == "true" ]] && return 0
    sleep 1
  done
  die "RDS가 목표 LSN까지 따라오지 못했습니다: $target"
}

app_backend() {
  printf '%s\n' "$RDS_APP_PASSWORD" | docker exec -i lookddak-pgbench sh -c '
    IFS= read -r PGPASSWORD
    export PGPASSWORD
    exec psql -X -v ON_ERROR_STOP=1 \
      "host=pgbouncer port=6432 dbname=lookddak_ai user=lookddak_app connect_timeout=5" \
      -Atc "SELECT current_database()||'\''|'\''||current_user||'\''|'\''||inet_server_port();"
  '
}

check_preconditions() {
  [[ "$(active_pgbouncer_backend)" == 'postgresql|5432|lookddak_ai||0' ]] \
    || die "PgBouncer가 PAUSE 해제된 EC2를 가리키지 않습니다"
  [[ "$(rds_admin_sql -Atc "SELECT subenabled::text FROM pg_subscription WHERE subname='${FORWARD_SUBSCRIPTION}';")" == "true" ]] \
    || die "정방향 구독이 활성화되어 있지 않습니다"
  [[ "$(ec2_admin_sql -Atc "SELECT subenabled::text FROM pg_subscription WHERE subname='${ROLLBACK_SUBSCRIPTION}';")" == "false" ]] \
    || die "롤백 구독은 비활성 상태여야 합니다"
  [[ "$(ec2_admin_sql -Atc "SELECT active::text FROM pg_replication_slots WHERE slot_name='${FORWARD_SLOT}';")" == "true" ]] \
    || die "정방향 슬롯이 active가 아닙니다"
  [[ "$(rds_admin_sql -Atc "SELECT count(*) FROM pg_replication_slots WHERE slot_name='${ROLLBACK_SLOT}';")" == "0" ]] \
    || die "롤백 슬롯이 전환 전에 이미 존재합니다"
  [[ "$(rds_admin_sql -Atc "SELECT count(*) FROM pg_subscription_rel r JOIN pg_subscription s ON s.oid=r.srsubid WHERE s.subname='${FORWARD_SUBSCRIPTION}' AND r.srsubstate<>'r';")" == "0" ]] \
    || die "정방향 구독에 ready가 아닌 테이블이 있습니다"
  test -f "${PGBOUNCER_DIR}/pgbouncer.rds.ini"
}

recover() {
  local rc=$?
  trap - ERR INT TERM
  set +e
  log "SWITCHOVER_FAILED exit_code=$rc rds_may_have_writes=$RDS_MAY_HAVE_WRITES"
  if [[ "$RDS_MAY_HAVE_WRITES" -eq 0 ]]; then
    if [[ "$DIRECTION_CHANGED" -eq 1 ]]; then
      ec2_admin_sql -c "ALTER SUBSCRIPTION ${ROLLBACK_SUBSCRIPTION} DISABLE;" >/dev/null 2>&1
      rds_admin_sql -c "ALTER SUBSCRIPTION ${FORWARD_SUBSCRIPTION} ENABLE;" >/dev/null 2>&1
    fi
    cp "${PGBOUNCER_DIR}/pgbouncer.ec2.ini" "${PGBOUNCER_DIR}/pgbouncer.ini"
    pgbouncer_admin 'RELOAD;' >/dev/null 2>&1
    pgbouncer_admin 'RECONNECT lookddak_ai;' >/dev/null 2>&1
    [[ "$PAUSED" -eq 0 ]] || pgbouncer_admin 'RESUME lookddak_ai;' >/dev/null 2>&1
    log "FAILSAFE=EC2 경로 복구 시도 완료; 상태를 즉시 확인하세요"
  else
    [[ "$PAUSED" -eq 0 ]] || pgbouncer_admin 'RESUME lookddak_ai;' >/dev/null 2>&1
    log "FAILSAFE=RDS가 쓰기를 받았으므로 RDS 경로를 유지합니다. 검증된 rollback만 사용하세요"
  fi
  cleanup_secrets
  exit "$rc"
}

check_preconditions
if [[ "$MODE" == "check" ]]; then
  log "CHECK_COMPLETE=run 모드는 실제 writer를 RDS로 변경합니다"
  exit 0
fi

acquire_migration_lock
start_run_log "$RUN_ID" switchover-to-rds
trap recover ERR INT TERM

pause_start=$SECONDS
timeout --foreground 10 bash -c \
  'docker exec lookddak-pgbouncer psql -X -v ON_ERROR_STOP=1 -h /var/run/pgbouncer -p 6432 -U pgbouncer_admin -d pgbouncer -c "PAUSE lookddak_ai;"'
PAUSED=1

target_lsn="$(ec2_admin_sql -Atc 'SELECT pg_current_wal_lsn();')"
wait_forward_catchup "$target_lsn"

IFS='|' read -r seq_value seq_called <<< "$(ec2_admin_sql -Atc 'SELECT last_value,is_called FROM public.products_id_seq;')"
rds_admin_sql -Atc "SELECT setval('public.products_id_seq',${seq_value},'${seq_called}'::boolean);" >/dev/null

rds_admin_sql -c "ALTER SUBSCRIPTION ${FORWARD_SUBSCRIPTION} DISABLE;" >/dev/null
DIRECTION_CHANGED=1
wait_slot ec2 "$FORWARD_SLOT" false
rds_admin_sql -Atc "SELECT pg_create_logical_replication_slot('${ROLLBACK_SLOT}','pgoutput');" >/dev/null
ec2_admin_sql -c "ALTER SUBSCRIPTION ${ROLLBACK_SUBSCRIPTION} ENABLE;" >/dev/null
wait_slot rds "$ROLLBACK_SLOT" true

cp "${PGBOUNCER_DIR}/pgbouncer.rds.ini" "${PGBOUNCER_DIR}/pgbouncer.ini"
pgbouncer_admin 'RELOAD;' >/dev/null
pgbouncer_admin 'RECONNECT lookddak_ai;' >/dev/null
[[ "$(active_pgbouncer_backend)" == "${RDS_HOST}|${RDS_PORT}|${RDS_DATABASE}||1" ]] \
  || die "PgBouncer RDS 대상 설정을 확인하지 못했습니다"

elapsed="$((SECONDS - pause_start))"
((elapsed <= MAX_PAUSE_SECONDS)) || die "PAUSE 시간이 ${MAX_PAUSE_SECONDS}초를 초과했습니다: ${elapsed}s"
pgbouncer_admin 'RESUME lookddak_ai;' >/dev/null
PAUSED=0
RDS_MAY_HAVE_WRITES=1

[[ "$(app_backend)" == "${RDS_DATABASE}|lookddak_app|${RDS_PORT}" ]] \
  || die "PgBouncer 경유 RDS 앱 연결 확인에 실패했습니다"
trap - ERR INT TERM
log "SWITCHOVER_SUCCEEDED target_lsn=$target_lsn pause_seconds=$elapsed forward=false reverse=true"
