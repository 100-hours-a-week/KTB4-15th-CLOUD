#!/usr/bin/env bash
# 운영 리허설용 저부하 pgbench 컨테이너와 장부 쓰기를 제어한다.
set -Eeuo pipefail
set +x

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common-functions.sh
source "${ROOT}/common-functions.sh"

ACTION="${1:-}"
RUN_ID="${2:-}"
RATE="${PGBENCH_RATE:-5}"
DURATION="${PGBENCH_DURATION_SECONDS:-600}"
CLIENTS="${PGBENCH_CLIENTS:-2}"

usage() {
  printf '사용법: %s {prepare|container-start|start|status|stop|finish} <작업-ID>\n' "$(basename "$0")"
}

case "$ACTION" in
  prepare|container-start|start|status|stop|finish) ;;
  *) usage; exit 2 ;;
esac
require_run_id "$RUN_ID"
require_root
require_commands aws docker flock grep

RESULT_DIR="${RESULT_ROOT}/${RUN_ID}"
PID_FILE="/results/${RUN_ID}/pgbench.pid"
LOG_FILE="${RESULT_DIR}/pgbench.log"
EXIT_FILE="${RESULT_DIR}/pgbench.exit"
DB_RUN_ID="${RUN_ID}-live"

is_running() {
  docker exec lookddak-pgbench sh -c '
    pid=$(cat "$1" 2>/dev/null) || exit 1
    kill -0 "$pid" 2>/dev/null && [ "$(cat /proc/$pid/comm 2>/dev/null)" = pgbench ]
  ' sh "$PID_FILE"
}

if [[ "$ACTION" == "prepare" ]]; then
  acquire_migration_lock
  ec2_admin_sql < "${PRODUCTION_MIGRATION_ROOT}/sql/create-migration-test-events.sql"
  log "PGBENCH_TABLE_READY=public.migration_test_events"
  exit 0
fi

if [[ "$ACTION" == "container-start" ]]; then
  acquire_migration_lock
  app_compose --profile migration up -d --no-deps pgbench
  require_healthy lookddak-pgbench
  log "PGBENCH_CONTAINER_READY=no workload started"
  exit 0
fi

require_healthy lookddak-pgbouncer
require_healthy lookddak-pgbench
install -d -o root -g root -m 0750 "$RESULT_DIR"

if [[ "$ACTION" == "status" ]]; then
  if is_running; then
    log "PGBENCH_RUNNING=true run_id=$DB_RUN_ID"
  else
    log "PGBENCH_RUNNING=false run_id=$DB_RUN_ID"
  fi
  tail -n 20 "$LOG_FILE" 2>/dev/null || true
  ec2_admin_sql -Atc "SELECT count(*)||'|'||count(DISTINCT event_id) FROM public.migration_test_events WHERE run_id='${DB_RUN_ID}';"
  exit 0
fi

acquire_migration_lock

if [[ "$ACTION" == "start" ]]; then
  [[ "$RATE" =~ ^[1-9][0-9]*$ && "$DURATION" =~ ^[1-9][0-9]*$ && "$CLIENTS" =~ ^[1-9][0-9]*$ ]] \
    || die "부하 설정값은 양의 정수여야 합니다"
  ! is_running || die "같은 작업 ID의 pgbench가 이미 실행 중입니다"
  [[ "$(ec2_admin_sql -Atc "SELECT to_regclass('public.migration_test_events') IS NOT NULL;")" == "t" ]] \
    || die "migration_test_events 테이블이 없습니다. prepare를 먼저 실행하세요"
  app_password="$(get_parameter "${PARAMETER_PREFIX}/app/password" true)"
  trap 'unset app_password' EXIT

  printf '%s\n' "$app_password" | docker exec -i lookddak-pgbench sh -c '
    IFS= read -r PGPASSWORD
    export PGPASSWORD PGHOST=pgbouncer PGPORT=6432 PGDATABASE=lookddak_ai PGUSER=lookddak_app PGAPPNAME=lookddak-prod-pgbench
    mkdir -p "/results/$1"
    nohup sh -c '\''
      pgbench -n -M simple -c "$3" -j "$3" -R "$4" -L 5000 -T "$5" -P 5 --progress-timestamp \
        -l --log-prefix="/results/$1/pgbench-tx" \
        -f /scripts/ledger.sql -D "run_id=$2" -D source_label=via_pgbouncer -D client_event_no=0 -D hold_sec=0 &
      pid=$!
      printf "%s\n" "$pid" > "/results/$1/pgbench.pid"
      wait "$pid"
      rc=$?
      printf "%s\n" "$rc" > "/results/$1/pgbench.exit"
      exit "$rc"
    '\'' sh "$1" "$2" "$3" "$4" "$5" > "/results/$1/pgbench.log" 2>&1 < /dev/null &
  ' sh "$RUN_ID" "$DB_RUN_ID" "$CLIENTS" "$RATE" "$DURATION"
  sleep 2
  is_running || die "pgbench 시작에 실패했습니다: $LOG_FILE"
  log "PGBENCH_STARTED run_id=$DB_RUN_ID rate=$RATE clients=$CLIENTS duration=$DURATION"
  exit 0
fi

if [[ "$ACTION" == "stop" ]]; then
  if is_running; then
    docker exec lookddak-pgbench sh -c 'kill -TERM "$(cat "$1")"' sh "$PID_FILE"
    log "PGBENCH_STOP_REQUESTED run_id=$DB_RUN_ID"
  else
    log "PGBENCH_ALREADY_STOPPED run_id=$DB_RUN_ID"
  fi
  exit 0
fi

is_running && die "pgbench가 아직 실행 중입니다"
[[ -f "$EXIT_FILE" && "$(cat "$EXIT_FILE")" == "0" ]] || die "pgbench가 정상 종료되지 않았습니다"
grep -Eq '^number of failed transactions: 0([ /]|$)' "$LOG_FILE" \
  || die "실패 트랜잭션이 있거나 요약을 찾지 못했습니다"
rows="$(ec2_admin_sql -Atc "SELECT count(*) FROM public.migration_test_events WHERE run_id='${DB_RUN_ID}';")"
unique="$(ec2_admin_sql -Atc "SELECT count(DISTINCT event_id) FROM public.migration_test_events WHERE run_id='${DB_RUN_ID}';")"
[[ "$rows" == "$unique" ]] || die "장부 이벤트가 중복되었습니다: rows=$rows unique=$unique"
log "PGBENCH_FINISHED run_id=$DB_RUN_ID rows=$rows unique=$unique"
