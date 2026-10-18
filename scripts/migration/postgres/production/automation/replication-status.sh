#!/usr/bin/env bash
# 정방향·역방향 구독, 슬롯, 지연, 오류 수를 읽기 전용으로 출력한다.
set -Eeuo pipefail
set +x

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common-functions.sh
source "${ROOT}/common-functions.sh"

require_root
require_commands aws docker
require_healthy lookddak-postgresql
require_healthy lookddak-pgbench
load_rds_parameters
trap cleanup_secrets EXIT

log "STATUS_UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
log "EC2_REPLICATION_BEGIN"
ec2_admin_sql -c "
  SELECT pubname,puballtables FROM pg_publication ORDER BY pubname;
  SELECT subname,subenabled,subslotname,suborigin FROM pg_subscription ORDER BY subname;
  SELECT slot_name,active,wal_status,safe_wal_size,confirmed_flush_lsn,
         pg_wal_lsn_diff(pg_current_wal_lsn(),confirmed_flush_lsn) AS lag_bytes
    FROM pg_replication_slots WHERE slot_type='logical' ORDER BY slot_name;
  SELECT subname,apply_error_count,sync_error_count FROM pg_stat_subscription_stats ORDER BY subname;
"
log "EC2_REPLICATION_END"

log "RDS_REPLICATION_BEGIN"
rds_admin_sql -c "
  SELECT pubname,puballtables FROM pg_publication ORDER BY pubname;
  SELECT subname,subenabled,subslotname,suborigin FROM pg_subscription ORDER BY subname;
  SELECT slot_name,active,wal_status,safe_wal_size,confirmed_flush_lsn,
         pg_wal_lsn_diff(pg_current_wal_lsn(),confirmed_flush_lsn) AS lag_bytes
    FROM pg_replication_slots WHERE slot_type='logical' ORDER BY slot_name;
  SELECT subname,pid,received_lsn,latest_end_lsn,latest_end_time
    FROM pg_stat_subscription ORDER BY subname,relid NULLS FIRST;
  SELECT subname,apply_error_count,sync_error_count FROM pg_stat_subscription_stats ORDER BY subname;
"
log "RDS_REPLICATION_END"
