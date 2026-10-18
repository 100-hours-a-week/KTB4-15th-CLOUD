#!/usr/bin/env bash
# 준비된 정방향 구독을 활성화하고 초기 복사 완료까지 관찰한다.
set -Eeuo pipefail
set +x

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common-functions.sh
source "${ROOT}/common-functions.sh"

MODE="${1:-}"
RUN_ID="${2:-}"
readonly INITIAL_COPY_TIMEOUT_SECONDS="${INITIAL_COPY_TIMEOUT_SECONDS:-1800}"

[[ "$MODE" == "check" || "$MODE" == "run" ]] \
  || die "사용법: $0 {check|run} <작업-ID>"
require_run_id "$RUN_ID"
require_root
require_commands aws docker flock python3
require_healthy lookddak-postgresql
require_healthy lookddak-pgbench
load_rds_parameters
trap cleanup_secrets EXIT

"${ROOT}/prepare-replication.py" verify
[[ "$(ec2_admin_sql -Atc "SELECT current_setting('wal_level');")" == "logical" ]] \
  || die "EC2 PostgreSQL wal_level이 logical이 아닙니다"

if [[ "$MODE" == "check" ]]; then
  log "CHECK_COMPLETE=run 모드는 정방향 슬롯 생성과 구독 활성화를 수행합니다"
  exit 0
fi

acquire_migration_lock
start_run_log "$RUN_ID" replication-start-forward

ec2_admin_sql -Atc "SELECT pg_create_logical_replication_slot('${FORWARD_SLOT}', 'pgoutput');"
rds_admin_sql -c "ALTER SUBSCRIPTION ${FORWARD_SUBSCRIPTION} ENABLE;"

deadline="$((SECONDS + INITIAL_COPY_TIMEOUT_SECONDS))"
while ((SECONDS < deadline)); do
  state="$(rds_admin_sql -Atc "
    SELECT count(*) FILTER (WHERE r.srsubstate='r') || '|' || count(*)
      FROM pg_subscription_rel r
      JOIN pg_subscription s ON s.oid=r.srsubid
     WHERE s.subname='${FORWARD_SUBSCRIPTION}';
  ")"
  worker="$(rds_admin_sql -Atc "SELECT count(*) FROM pg_stat_subscription WHERE subname='${FORWARD_SUBSCRIPTION}' AND pid IS NOT NULL;")"
  log "FORWARD_PROGRESS ready_total=$state workers=$worker"
  if [[ "$state" == '7|7' && "$worker" -ge 1 ]]; then
    break
  fi
  sleep 10
done

[[ "$state" == '7|7' ]] || die "초기 복사가 제한 시간 안에 끝나지 않았습니다: $state"
[[ "$(ec2_admin_sql -Atc "SELECT active::text FROM pg_replication_slots WHERE slot_name='${FORWARD_SLOT}';")" == "true" ]] \
  || die "정방향 복제 슬롯이 active가 아닙니다"
[[ "$(ec2_admin_sql -Atc "SELECT subenabled::text FROM pg_subscription WHERE subname='${ROLLBACK_SUBSCRIPTION}';")" == "false" ]] \
  || die "롤백 구독이 비활성 상태가 아닙니다"

log "FORWARD_REPLICATION_STARTED ready_tables=7 reverse_subscription=false"
