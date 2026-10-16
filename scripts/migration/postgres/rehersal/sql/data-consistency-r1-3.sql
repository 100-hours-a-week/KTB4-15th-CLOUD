\set ON_ERROR_STOP on
\if :{?run_id}
\else
\echo 'ERROR: -v run_id=<value> is required'
\quit 2
\endif

\pset pager off
\pset tuples_only on
\pset format unaligned
\pset fieldsep '|'
\pset footer off

BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;
SET LOCAL TIME ZONE 'UTC';
SET LOCAL bytea_output = 'hex';
SET LOCAL extra_float_digits = 3;

-- The first line compares pgbench success count with committed ledger rows.
SELECT 'LEDGER_SUMMARY',
       :'run_id',
       count(*)::text,
       count(DISTINCT event_id)::text,
       (count(*) - count(DISTINCT event_id))::text,
       md5(COALESCE(string_agg(md5(row_to_json(t)::text), '' ORDER BY event_id), ''))
FROM public.migration_test_events AS t
WHERE run_id = :'run_id';

-- Normally empty because both the primary key and logical event key are unique.
SELECT 'LEDGER_DUPLICATE',
       :'run_id',
       client_id::text,
       event_no::text,
       count(*)::text
FROM public.migration_test_events
WHERE run_id = :'run_id'
GROUP BY client_id, event_no
HAVING count(*) > 1
ORDER BY client_id, event_no;

-- Diffing the EC2 and RDS outputs reveals the exact missing or changed event ID.
SELECT 'LEDGER_EVENT',
       event_id,
       md5(row_to_json(t)::text)
FROM public.migration_test_events AS t
WHERE run_id = :'run_id'
ORDER BY event_id;

-- Run only after writes are paused and the publisher target LSN is reached.
SELECT 'TABLE_CHECKSUM', 'public.products', count(*)::text,
       md5(COALESCE(string_agg(md5(row_to_json(t)::text), '' ORDER BY id), ''))
FROM public.products AS t;

SELECT 'TABLE_CHECKSUM', 'public.usage_amount', count(*)::text,
       md5(COALESCE(string_agg(md5(row_to_json(t)::text), '' ORDER BY usage_date), ''))
FROM public.usage_amount AS t;

SELECT 'TABLE_CHECKSUM', 'public.migration_test_events', count(*)::text,
       md5(COALESCE(string_agg(md5(row_to_json(t)::text), '' ORDER BY event_id), ''))
FROM public.migration_test_events AS t;

SELECT 'TABLE_CHECKSUM', 'langgraph.checkpoint_blobs', count(*)::text,
       md5(COALESCE(string_agg(md5(row_to_json(t)::text), '' ORDER BY thread_id, checkpoint_ns, channel, version), ''))
FROM langgraph.checkpoint_blobs AS t;

SELECT 'TABLE_CHECKSUM', 'langgraph.checkpoint_migrations', count(*)::text,
       md5(COALESCE(string_agg(md5(row_to_json(t)::text), '' ORDER BY v), ''))
FROM langgraph.checkpoint_migrations AS t;

SELECT 'TABLE_CHECKSUM', 'langgraph.checkpoint_writes', count(*)::text,
       md5(COALESCE(string_agg(md5(row_to_json(t)::text), '' ORDER BY thread_id, checkpoint_ns, checkpoint_id, task_id, idx), ''))
FROM langgraph.checkpoint_writes AS t;

SELECT 'TABLE_CHECKSUM', 'langgraph.checkpoints', count(*)::text,
       md5(COALESCE(string_agg(md5(row_to_json(t)::text), '' ORDER BY thread_id, checkpoint_ns, checkpoint_id), ''))
FROM langgraph.checkpoints AS t;

COMMIT;
