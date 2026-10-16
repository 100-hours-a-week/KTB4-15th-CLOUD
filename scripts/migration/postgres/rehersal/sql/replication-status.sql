\set ON_ERROR_STOP on
\pset pager off
\pset null '(null)'

SET TIME ZONE 'UTC';

SELECT clock_timestamp() AS captured_at_utc,
       current_database() AS database_name,
       pg_is_in_recovery() AS is_standby;

-- Run on the publisher. lag_bytes is how much WAL the subscriber has not yet
-- confirmed. safe_wal_size approaching zero means the configured WAL limit is close.
SELECT slot_name,
       active,
       restart_lsn,
       confirmed_flush_lsn,
       wal_status,
       safe_wal_size,
       pg_current_wal_lsn() AS current_wal_lsn,
       CASE WHEN confirmed_flush_lsn IS NULL THEN NULL
            ELSE pg_wal_lsn_diff(pg_current_wal_lsn(), confirmed_flush_lsn)
       END AS lag_bytes,
       CASE WHEN confirmed_flush_lsn IS NULL THEN NULL
            ELSE pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), confirmed_flush_lsn)::bigint)
       END AS lag_pretty
FROM pg_replication_slots
WHERE slot_type = 'logical'
ORDER BY slot_name;

-- Run on the subscriber. No row, or a NULL pid, means no apply worker is active.
SELECT subname,
       pid,
       relid::regclass AS syncing_table,
       received_lsn,
       last_msg_send_time,
       last_msg_receipt_time,
       latest_end_lsn,
       latest_end_time,
       CASE WHEN latest_end_time IS NULL THEN NULL
            ELSE round(extract(epoch FROM clock_timestamp() - latest_end_time)::numeric, 3)
       END AS seconds_since_latest_end
FROM pg_stat_subscription
ORDER BY subname, relid NULLS FIRST;

SELECT subname,
       apply_error_count,
       sync_error_count,
       stats_reset
FROM pg_stat_subscription_stats
ORDER BY subname;

SELECT s.subname,
       s.subenabled,
       count(r.srrelid) AS registered_tables,
       count(*) FILTER (WHERE r.srsubstate = 'r') AS ready_tables,
       count(*) FILTER (WHERE r.srsubstate <> 'r') AS not_ready_tables
FROM pg_subscription s
LEFT JOIN pg_subscription_rel r ON r.srsubid = s.oid
WHERE s.subdbid = (SELECT oid FROM pg_database WHERE datname = current_database())
GROUP BY s.subname, s.subenabled
ORDER BY s.subname;

-- Open transactions matter because PgBouncer PAUSE waits for them to finish.
SELECT pid,
       usename,
       application_name,
       client_addr,
       state,
       wait_event_type,
       wait_event,
       xact_start,
       round(extract(epoch FROM clock_timestamp() - xact_start)::numeric, 3) AS transaction_age_seconds
FROM pg_stat_activity
WHERE xact_start IS NOT NULL
  AND pid <> pg_backend_pid()
ORDER BY xact_start;

-- At cutover, pass -v target_lsn=0/16B6C50. reached_target must be true.
\if :{?target_lsn}
SELECT slot_name,
       :'target_lsn'::pg_lsn AS target_lsn,
       confirmed_flush_lsn,
       confirmed_flush_lsn >= :'target_lsn'::pg_lsn AS reached_target,
       GREATEST(pg_wal_lsn_diff(:'target_lsn'::pg_lsn, confirmed_flush_lsn), 0) AS bytes_remaining_to_target
FROM pg_replication_slots
WHERE slot_type = 'logical'
ORDER BY slot_name;
\endif
