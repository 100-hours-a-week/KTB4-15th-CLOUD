\set ON_ERROR_STOP on

CREATE TABLE IF NOT EXISTS public.migration_test_events (
  event_id text PRIMARY KEY,
  run_id text NOT NULL,
  client_id integer NOT NULL,
  event_no bigint NOT NULL,
  payload jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE (run_id, client_id, event_no)
);

CREATE INDEX IF NOT EXISTS migration_test_events_run_id_idx
  ON public.migration_test_events (run_id);

GRANT SELECT, INSERT, UPDATE, DELETE ON public.migration_test_events TO lookddak_app;
GRANT SELECT ON public.migration_test_events TO lookddak_migration;
