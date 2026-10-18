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
SELECT pg_sleep(:hold_sec);
COMMIT;
