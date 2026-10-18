#!/usr/bin/env bash
set -Eeuo pipefail

# Dev PostgreSQL 리허설의 EC2 -> RDS 전환을 짧은 PAUSE 안에 실행한다.
# pgbench는 수정하지 않고 계속 실행하며, 전환 전후에 같은 프로세스와 쓰기가 유지되는지 확인한다.

SCRIPT_NAME="$(basename "$0")"
MODE="${1:-}"
RESULT_RUN_ID="${2:-}"
REGION="${AWS_REGION:-ap-northeast-2}"
REHEARSAL_ROOT="${REHEARSAL_ROOT:-/opt/lookddak/scripts/migration/postgres/rehearsal}"
PGBOUNCER_DIR="${PGBOUNCER_DIR:-/opt/lookddak/pgbouncer}"
MAX_PAUSE_SECONDS="${MAX_PAUSE_SECONDS:-30}"
PAUSE_DRAIN_TIMEOUT_SECONDS="${PAUSE_DRAIN_TIMEOUT_SECONDS:-10}"
FORWARD_CATCHUP_TIMEOUT_SECONDS="${FORWARD_CATCHUP_TIMEOUT_SECONDS:-10}"
ROLLBACK_SLOT_TIMEOUT_SECONDS="${ROLLBACK_SLOT_TIMEOUT_SECONDS:-10}"
POST_SWITCH_OBSERVE_SECONDS="${POST_SWITCH_OBSERVE_SECONDS:-15}"
DB_RUN_ID="${DB_RUN_ID:-${RESULT_RUN_ID}-live}"

FWD_SUB="lookddak_pg_forward_sub"
REV_SUB="lookddak_pg_rollback_sub"
FWD_SLOT="lookddak_pg_forward_slot"
REV_SLOT="lookddak_pg_rollback_slot"

PAUSE_REQUESTED=0
DIRECTION_SWITCHED=0
ROLLBACK_SLOT_CREATED=0
COMPLETED=0
RDS_MAY_HAVE_WRITES=0

usage() {
  cat <<EOF
사용법:
  $SCRIPT_NAME check <result-run-id>
  $SCRIPT_NAME run   <result-run-id>

예시:
  $SCRIPT_NAME check r2-20261016-01
  $SCRIPT_NAME run   r2-20261016-01

기본 경로:
  PID:  /results/<result-run-id>/pgbench-live.pid
  로그: $REHEARSAL_ROOT/results/<result-run-id>/pgbench-live.log

선택 환경 변수:
  DB_RUN_ID, MAX_PAUSE_SECONDS, POST_SWITCH_OBSERVE_SECONDS
EOF
}

fail() {
  echo "STOP=$*" >&2
  return 1
}

pgb_admin() {
  sudo docker exec lookddak-pgbouncer psql -X -v ON_ERROR_STOP=1 \
    -h /var/run/pgbouncer -p 6432 -U pgbouncer_admin -d pgbouncer -c "$1"
}

ec2_sql() {
  sudo docker exec lookddak-postgresql psql -X -v ON_ERROR_STOP=1 \
    -U lookddak_ai_app -d lookddak_ai "$@"
}

rds_sql() {
  sudo docker exec -e PGPASSWORD="$RDS_ADMIN_PASSWORD" lookddak-pgbench \
    psql -X -v ON_ERROR_STOP=1 "$RDS_DSN" "$@"
}

pgbench_is_running() {
  sudo docker exec lookddak-pgbench sh -c \
    'PID=$(cat "$1" 2>/dev/null) && kill -0 "$PID" 2>/dev/null' sh "$PGBENCH_PID_IN_CONTAINER"
}

count_log_errors() {
  { sudo grep -Eic 'FATAL:|ERROR:|Run was aborted|connection .* failed|timeout expired' "$PGBENCH_LOG_ON_HOST" || true; } | tail -n 1
}

count_progress_lines() {
  { sudo grep -Ec '^progress:' "$PGBENCH_LOG_ON_HOST" || true; } | tail -n 1
}

wait_pgbouncer_healthy() {
  local attempt status
  for attempt in $(seq 1 30); do
    status="$(sudo docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' lookddak-pgbouncer 2>/dev/null || true)"
    [ "$status" = "healthy" ] && return 0
    sleep 1
  done
  return 1
}

restore_ec2_after_failure() {
  set +e
  if [ "$RDS_MAY_HAVE_WRITES" -eq 1 ]; then
    echo "FAILSAFE_RDS_RETAINED=RDS may have accepted writes; do not restore EC2 before reverse catchup"
    pgb_admin "RESUME lookddak_ai;" >/dev/null 2>&1
    echo "NEXT=run r1-3-tools.sh status, then perform a verified rollback; do not restart pgbench under this run ID"
    return
  fi
  echo "FAILSAFE_BEGIN=restore EC2 service path"

  if [ "$DIRECTION_SWITCHED" -eq 1 ]; then
    ec2_sql -c "ALTER SUBSCRIPTION $REV_SUB DISABLE;" >/dev/null 2>&1

    for _ in $(seq 1 10); do
      slot_active="$(rds_sql -Atc "SELECT COALESCE((SELECT active::text FROM pg_replication_slots WHERE slot_name='$REV_SLOT'), 'missing');" 2>/dev/null)"
      [ "$slot_active" != "true" ] && break
      sleep 1
    done

    if [ "$ROLLBACK_SLOT_CREATED" -eq 1 ]; then
      rds_sql -Atc "SELECT pg_drop_replication_slot(slot_name) FROM pg_replication_slots WHERE slot_name='$REV_SLOT' AND NOT active;" >/dev/null 2>&1
    fi

    rds_sql -c "ALTER SUBSCRIPTION $FWD_SUB ENABLE;" >/dev/null 2>&1
  fi

  if [ "$PAUSE_REQUESTED" -eq 1 ]; then
    sudo sh -c "cat '$PGBOUNCER_DIR/pgbouncer.ec2.ini' > '$PGBOUNCER_DIR/pgbouncer.ini'"
    sudo docker restart lookddak-pgbouncer >/dev/null 2>&1
    wait_pgbouncer_healthy
  fi

  echo "FAILSAFE_END=EC2 path recovery attempted"
}

on_error() {
  local rc=$?
  trap - ERR INT TERM
  echo "SWITCHOVER_FAILED phase=${PHASE:-unknown} exit_code=$rc" >&2
  if [ "$COMPLETED" -eq 0 ]; then
    restore_ec2_after_failure
  fi
  exit "$rc"
}

if [ "$MODE" != "check" ] && [ "$MODE" != "run" ]; then
  usage
  exit 2
fi

if ! [[ "$RESULT_RUN_ID" =~ ^[A-Za-z0-9._-]+$ ]]; then
  fail "result-run-id는 영문자, 숫자, 점, 밑줄, 하이픈만 사용할 수 있습니다"
  exit 2
fi

RESULT_DIR="$REHEARSAL_ROOT/results/$RESULT_RUN_ID"
PGBENCH_PID_IN_CONTAINER="/results/$RESULT_RUN_ID/pgbench-live.pid"
PGBENCH_LOG_ON_HOST="$RESULT_DIR/pgbench-live.log"
sudo mkdir -p "$RESULT_DIR"

if [ "$MODE" = "run" ]; then
  exec 9>/tmp/lookddak-postgresql-switchover.lock
  flock -n 9 || { fail "다른 전환 작업이 실행 중입니다"; exit 1; }
  RUN_LOG="$RESULT_DIR/switchover-to-rds-$(date -u +%Y%m%dT%H%M%SZ).log"
  exec > >(sudo tee -a "$RUN_LOG") 2>&1
fi

trap on_error ERR INT TERM

PHASE="load-configuration"
RDS_HOST="$(aws ssm get-parameter --region "$REGION" --name /lookddak/dev/v2/postgresql/host --query 'Parameter.Value' --output text)"
RDS_PORT="$(aws ssm get-parameter --region "$REGION" --name /lookddak/dev/v2/postgresql/port --query 'Parameter.Value' --output text)"
RDS_DB="$(aws ssm get-parameter --region "$REGION" --name /lookddak/dev/v2/postgresql/database --query 'Parameter.Value' --output text)"
RDS_ADMIN="$(aws ssm get-parameter --region "$REGION" --name /lookddak/dev/v2/postgresql/admin/username --query 'Parameter.Value' --output text)"
RDS_ADMIN_PASSWORD="$(aws ssm get-parameter --region "$REGION" --name /lookddak/dev/v2/postgresql/admin/password --with-decryption --query 'Parameter.Value' --output text)"
RDS_APP_PASSWORD="$(aws ssm get-parameter --region "$REGION" --name /lookddak/dev/v2/postgresql/app/password --with-decryption --query 'Parameter.Value' --output text)"
RDS_DSN="host=$RDS_HOST port=$RDS_PORT dbname=$RDS_DB user=$RDS_ADMIN sslmode=require connect_timeout=5"
test -n "$RDS_ADMIN_PASSWORD" && test -n "$RDS_APP_PASSWORD"

PHASE="preflight"
[ "$(rds_sql -Atc "SELECT suborigin FROM pg_subscription WHERE subname='$FWD_SUB';")" = "none" ] || fail "forward subscription origin must be none"
[ "$(ec2_sql -Atc "SELECT suborigin FROM pg_subscription WHERE subname='$REV_SUB';")" = "none" ] || fail "reverse subscription origin must be none"
for container in lookddak-postgresql lookddak-pgbouncer lookddak-pgbench lookddak-fastapi lookddak-nginx; do
  status="$(sudo docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$container")"
  [ "$status" = "healthy" ] || fail "$container 상태가 healthy가 아닙니다: $status"
done

sudo test -f "$PGBOUNCER_DIR/pgbouncer.ec2.ini" || fail "EC2용 PgBouncer 설정 파일이 없습니다"
sudo test -f "$PGBOUNCER_DIR/pgbouncer.rds.ini" || fail "RDS용 PgBouncer 설정 파일이 없습니다"
sudo grep -Fxq 'lookddak_ai = host=postgresql port=5432 dbname=lookddak_ai' "$PGBOUNCER_DIR/pgbouncer.ec2.ini" || fail "EC2용 PgBouncer 설정 내용이 예상과 다릅니다"
sudo grep -Fxq "lookddak_ai = host=$RDS_HOST port=$RDS_PORT dbname=$RDS_DB" "$PGBOUNCER_DIR/pgbouncer.rds.ini" || fail "RDS용 PgBouncer 설정 내용이 예상과 다릅니다"

PGBOUNCER_BEFORE="$(sudo docker exec lookddak-pgbouncer psql -X -h /var/run/pgbouncer -p 6432 -U pgbouncer_admin -d pgbouncer -Atc 'SHOW DATABASES;' | awk -F'|' '$1 == "lookddak_ai" {print $2 "|" $3 "|" $4 "|" $5 "|" $16}')"
[ "$PGBOUNCER_BEFORE" = "postgresql|5432|lookddak_ai||0" ] || fail "PgBouncer가 PAUSE 해제된 EC2 상태가 아닙니다: $PGBOUNCER_BEFORE"

FWD_SUB_ENABLED="$(rds_sql -Atc "SELECT subenabled::text FROM pg_subscription WHERE subname='$FWD_SUB';")"
REV_SUB_ENABLED="$(ec2_sql -Atc "SELECT subenabled::text FROM pg_subscription WHERE subname='$REV_SUB';")"
FWD_SLOT_STATE="$(ec2_sql -Atc "SELECT COALESCE((SELECT active::text FROM pg_replication_slots WHERE slot_name='$FWD_SLOT'), 'missing');")"
REV_SLOT_STATE="$(rds_sql -Atc "SELECT COALESCE((SELECT active::text FROM pg_replication_slots WHERE slot_name='$REV_SLOT'), 'missing');")"
NOT_READY_TABLES="$(rds_sql -Atc "SELECT count(*) FROM pg_subscription_rel r JOIN pg_subscription s ON s.oid=r.srsubid WHERE s.subname='$FWD_SUB' AND r.srsubstate <> 'r';")"
REGISTERED_TABLES="$(rds_sql -Atc "SELECT count(*) FROM pg_subscription_rel r JOIN pg_subscription s ON s.oid=r.srsubid WHERE s.subname='$FWD_SUB';")"

[ "$FWD_SUB_ENABLED" = "true" ] || fail "정방향 구독이 활성화되어 있지 않습니다"
[ "$REV_SUB_ENABLED" = "false" ] || fail "역방향 구독은 전환 전 비활성화 상태여야 합니다"
[ "$FWD_SLOT_STATE" = "true" ] || fail "정방향 복제 슬롯이 active 상태가 아닙니다: $FWD_SLOT_STATE"
[ "$REV_SLOT_STATE" = "missing" ] || fail "역방향 슬롯이 전환 전에 이미 존재합니다: $REV_SLOT_STATE"
[ "$REGISTERED_TABLES" = "7" ] || fail "정방향 구독에 등록된 테이블 수가 7개가 아닙니다: $REGISTERED_TABLES"
[ "$NOT_READY_TABLES" = "0" ] || fail "정방향 구독에서 ready가 아닌 테이블이 있습니다: $NOT_READY_TABLES"
pgbench_is_running || fail "pgbench-live 프로세스가 실행 중이 아닙니다: $PGBENCH_PID_IN_CONTAINER"
sudo test -f "$PGBENCH_LOG_ON_HOST" || fail "pgbench 로그가 없습니다: $PGBENCH_LOG_ON_HOST"

ERRORS_BEFORE="$(count_log_errors)"
PROGRESS_BEFORE="$(count_progress_lines)"
[ "$ERRORS_BEFORE" = "0" ] || fail "pgbench already has errors; use a new run ID after diagnosing"
COUNT_BEFORE="$(ec2_sql -Atc "SELECT count(*) FROM public.migration_test_events WHERE run_id='$DB_RUN_ID';")"

echo "PRECHECK_OK result_run_id=$RESULT_RUN_ID db_run_id=$DB_RUN_ID"
echo "PRECHECK_REPLICATION forward_sub=$FWD_SUB_ENABLED forward_slot=$FWD_SLOT_STATE reverse_sub=$REV_SUB_ENABLED reverse_slot=$REV_SLOT_STATE"
echo "PRECHECK_PGBENCH pid_alive=true rows=$COUNT_BEFORE errors=$ERRORS_BEFORE progress_lines=$PROGRESS_BEFORE"

if [ "$MODE" = "check" ]; then
  trap - ERR INT TERM
  unset RDS_ADMIN_PASSWORD RDS_APP_PASSWORD
  echo "CHECK_COMPLETE=run 모드를 실행할 준비가 됐습니다"
  exit 0
fi

PHASE="pause-pgbouncer"
PAUSE_REQUESTED=1
PAUSE_STARTED_EPOCH="$(date +%s)"
PAUSE_STARTED_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
timeout "$PAUSE_DRAIN_TIMEOUT_SECONDS" sudo docker exec lookddak-pgbouncer \
  psql -X -v ON_ERROR_STOP=1 -h /var/run/pgbouncer -p 6432 -U pgbouncer_admin -d pgbouncer -c "PAUSE lookddak_ai;"
echo "PAUSE_COMPLETE_UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)"

PHASE="wait-forward-catchup"
TARGET_LSN="$(ec2_sql -Atc 'SELECT pg_current_wal_lsn();')"
FORWARD_CAUGHT_UP=0
for attempt in $(seq 1 "$FORWARD_CATCHUP_TIMEOUT_SECONDS"); do
  reached="$(ec2_sql -Atc "SELECT COALESCE((SELECT (confirmed_flush_lsn >= '$TARGET_LSN'::pg_lsn)::text FROM pg_replication_slots WHERE slot_name='$FWD_SLOT'), 'false');")"
  if [ "$reached" = "true" ]; then
    FORWARD_CAUGHT_UP=1
    break
  fi
  sleep 1
done
[ "$FORWARD_CAUGHT_UP" -eq 1 ] || fail "RDS가 목표 WAL까지 따라오지 못했습니다: $TARGET_LSN"
echo "FORWARD_CAUGHT_UP target_lsn=$TARGET_LSN attempt=$attempt"

PHASE="sync-sequence"
IFS='|' read -r EC2_SEQ_VALUE EC2_SEQ_CALLED <<< "$(ec2_sql -Atc 'SELECT last_value, is_called FROM public.products_id_seq;')"
if [ "$EC2_SEQ_CALLED" = "t" ]; then
  EC2_SEQ_SQL_BOOL=true
elif [ "$EC2_SEQ_CALLED" = "f" ]; then
  EC2_SEQ_SQL_BOOL=false
else
  fail "products_id_seq의 is_called 값이 올바르지 않습니다: $EC2_SEQ_CALLED"
fi
rds_sql -Atc "SELECT setval('public.products_id_seq', $EC2_SEQ_VALUE, $EC2_SEQ_SQL_BOOL);" >/dev/null
echo "SEQUENCE_SYNCED value=$EC2_SEQ_VALUE is_called=$EC2_SEQ_SQL_BOOL"

PHASE="switch-replication-direction"
rds_sql -c "ALTER SUBSCRIPTION $FWD_SUB DISABLE;" >/dev/null
DIRECTION_SWITCHED=1

for attempt in $(seq 1 10); do
  state="$(ec2_sql -Atc "SELECT COALESCE((SELECT active::text FROM pg_replication_slots WHERE slot_name='$FWD_SLOT'), 'missing');")"
  [ "$state" = "false" ] && break
  sleep 1
done
[ "$state" = "false" ] || fail "정방향 슬롯이 비활성화되지 않았습니다: $state"

rds_sql -Atc "SELECT pg_create_logical_replication_slot('$REV_SLOT', 'pgoutput');" >/dev/null
ROLLBACK_SLOT_CREATED=1
ec2_sql -c "ALTER SUBSCRIPTION $REV_SUB ENABLE;" >/dev/null

ROLLBACK_ACTIVE=0
for attempt in $(seq 1 "$ROLLBACK_SLOT_TIMEOUT_SECONDS"); do
  state="$(rds_sql -Atc "SELECT COALESCE((SELECT active::text FROM pg_replication_slots WHERE slot_name='$REV_SLOT'), 'missing');")"
  if [ "$state" = "true" ]; then
    ROLLBACK_ACTIVE=1
    break
  fi
  sleep 1
done
[ "$ROLLBACK_ACTIVE" -eq 1 ] || fail "역방향 복제 슬롯이 active 상태가 되지 않았습니다: $state"
echo "REPLICATION_DIRECTION_SWITCHED forward=false reverse=true"

PHASE="switch-pgbouncer-to-rds"
sudo sh -c "cat '$PGBOUNCER_DIR/pgbouncer.rds.ini' > '$PGBOUNCER_DIR/pgbouncer.ini'"
pgb_admin "RELOAD;" >/dev/null
pgb_admin "RECONNECT lookddak_ai;" >/dev/null

PGBOUNCER_RDS_STATE="$(sudo docker exec lookddak-pgbouncer psql -X -h /var/run/pgbouncer -p 6432 -U pgbouncer_admin -d pgbouncer -Atc 'SHOW DATABASES;' | awk -F'|' '$1 == "lookddak_ai" {print $2 "|" $3 "|" $4 "|" $5 "|" $16}')"
[ "$PGBOUNCER_RDS_STATE" = "$RDS_HOST|$RDS_PORT|$RDS_DB||1" ] || fail "PgBouncer RDS 설정이 예상과 다릅니다: $PGBOUNCER_RDS_STATE"

PHASE="resume-pgbouncer"
RDS_MAY_HAVE_WRITES=1
pgb_admin "RESUME lookddak_ai;" >/dev/null
PAUSE_ENDED_EPOCH="$(date +%s)"
PAUSE_SECONDS="$((PAUSE_ENDED_EPOCH - PAUSE_STARTED_EPOCH))"
[ "$PAUSE_SECONDS" -le "$MAX_PAUSE_SECONDS" ] || fail "PAUSE 시간이 목표를 초과했습니다: ${PAUSE_SECONDS}s > ${MAX_PAUSE_SECONDS}s"
echo "RESUME_COMPLETE_UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ) pause_seconds=$PAUSE_SECONDS"

PHASE="verify-rds-connection"
BACKEND="$(timeout 10 sudo docker exec -e PGPASSWORD="$RDS_APP_PASSWORD" lookddak-pgbench \
  psql -X -v ON_ERROR_STOP=1 "host=pgbouncer port=6432 dbname=lookddak_ai user=lookddak_app connect_timeout=5" \
  -Atc "SELECT current_database() || '|' || current_user || '|' || inet_server_port();")"
[ "$BACKEND" = "lookddak|lookddak_app|$RDS_PORT" ] || fail "PgBouncer 경유 RDS 연결 결과가 예상과 다릅니다: $BACKEND"
echo "RDS_CONNECTION_OK backend=$BACKEND"

PHASE="verify-existing-pgbench"
sleep "$POST_SWITCH_OBSERVE_SECONDS"
pgbench_is_running || fail "전환 후 기존 pgbench 프로세스가 종료됐습니다"

ERRORS_AFTER="$(count_log_errors)"
PROGRESS_AFTER="$(count_progress_lines)"
RDS_COUNT_AFTER="$(rds_sql -Atc "SELECT count(*) FROM public.migration_test_events WHERE run_id='$DB_RUN_ID';")"

[ "$ERRORS_AFTER" = "$ERRORS_BEFORE" ] || fail "전환 후 pgbench 로그에 새 오류가 생겼습니다: before=$ERRORS_BEFORE after=$ERRORS_AFTER"
[ "$PROGRESS_AFTER" -gt "$PROGRESS_BEFORE" ] || fail "전환 후 pgbench 진행 로그가 증가하지 않았습니다"
[ "$RDS_COUNT_AFTER" -gt "$COUNT_BEFORE" ] || fail "전환 후 RDS의 쓰기 데이터가 증가하지 않았습니다: before=$COUNT_BEFORE after=$RDS_COUNT_AFTER"

REVERSE_REACHED=0
for attempt in $(seq 1 10); do
  EC2_COUNT_AFTER="$(ec2_sql -Atc "SELECT count(*) FROM public.migration_test_events WHERE run_id='$DB_RUN_ID';")"
  if [ "$EC2_COUNT_AFTER" -ge "$RDS_COUNT_AFTER" ]; then
    REVERSE_REACHED=1
    break
  fi
  sleep 1
done
[ "$REVERSE_REACHED" -eq 1 ] || fail "역방향 복제가 RDS 확인 지점까지 따라오지 못했습니다: rds=$RDS_COUNT_AFTER ec2=$EC2_COUNT_AFTER"

COMPLETED=1
trap - ERR INT TERM
unset RDS_ADMIN_PASSWORD RDS_APP_PASSWORD
echo "PGBENCH_CONTINUITY_OK pid_alive=true new_errors=0 progress_added=$((PROGRESS_AFTER - PROGRESS_BEFORE))"
echo "LIVE_WRITES_OK before=$COUNT_BEFORE rds_after=$RDS_COUNT_AFTER ec2_after=$EC2_COUNT_AFTER"
echo "SWITCHOVER_TO_RDS_SUCCEEDED pause_seconds=$PAUSE_SECONDS"
