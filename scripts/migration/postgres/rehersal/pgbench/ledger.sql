-- Required pgbench variables:
--   run_id, source_label, client_event_no, hold_sec
-- Normal load:        -D client_event_no=0 -D hold_sec=0
-- Long transaction:   -D client_event_no=0 -D hold_sec=30 -c 1 -t 1
-- client_event_no is maintained independently by each pgbench client.
-- Keep run_id and source_label to letters, digits, underscore and hyphen.

\set client_event_no :client_event_no + 1

BEGIN;

INSERT INTO public.migration_test_events (
    event_id,
    run_id,
    client_id,
    event_no,
    payload
)
VALUES (
    concat(':run_id', '-', :client_id, '-', :client_event_no),
    ':run_id',
    :client_id,
    :client_event_no,
    jsonb_build_object(
        'source', ':source_label',
        'client_id', :client_id,
        'event_no', :client_event_no,
        'hold_sec', :hold_sec
    )
);

-- hold_sec=0 is the normal write load. A positive value intentionally keeps
-- the transaction open so PgBouncer PAUSE behavior can be observed.
SELECT pg_sleep(:hold_sec);

COMMIT;
