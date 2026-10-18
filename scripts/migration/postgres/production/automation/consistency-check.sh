#!/usr/bin/env bash
# PAUSE 및 목표 LSN 도달 후 EC2와 RDS의 7개 테이블 결과를 비교한다.
set -Eeuo pipefail
set +x

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common-functions.sh
source "${ROOT}/common-functions.sh"

RUN_ID="${1:-}"
DB_RUN_ID="${2:-${RUN_ID}-live}"
require_run_id "$RUN_ID"
require_run_id "$DB_RUN_ID"
require_root
require_commands aws diff docker flock
require_healthy lookddak-postgresql
require_healthy lookddak-pgbench
load_rds_parameters
trap cleanup_secrets EXIT
acquire_migration_lock
start_run_log "$RUN_ID" consistency-check

result_dir="${RESULT_ROOT}/${RUN_ID}"
ec2_result="${result_dir}/consistency-ec2.txt"
rds_result="${result_dir}/consistency-rds.txt"
diff_result="${result_dir}/consistency.diff"

ec2_admin_sql -v "run_id=${DB_RUN_ID}" < "${PRODUCTION_MIGRATION_ROOT}/sql/data-consistency.sql" > "$ec2_result"
rds_admin_sql -v "run_id=${DB_RUN_ID}" < "${PRODUCTION_MIGRATION_ROOT}/sql/data-consistency.sql" > "$rds_result"

if ! diff -u "$ec2_result" "$rds_result" > "$diff_result"; then
  die "EC2와 RDS 데이터가 다릅니다: $diff_result"
fi
rm -f "$diff_result"
log "CONSISTENCY_SUCCEEDED run_id=$DB_RUN_ID tables=7"
