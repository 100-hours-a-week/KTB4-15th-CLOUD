\set ON_ERROR_STOP on
\getenv lookddak_migration_password LOOKDDAK_MIGRATION_PASSWORD

DO $role$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'lookddak_migration') THEN
    CREATE ROLE lookddak_migration LOGIN REPLICATION;
  END IF;
END
$role$;

ALTER ROLE lookddak_migration LOGIN REPLICATION PASSWORD :'lookddak_migration_password';
GRANT CONNECT ON DATABASE lookddak_ai TO lookddak_migration;
GRANT USAGE ON SCHEMA public, langgraph TO lookddak_migration;
GRANT SELECT ON ALL TABLES IN SCHEMA public, langgraph TO lookddak_migration;
GRANT SELECT ON ALL SEQUENCES IN SCHEMA public, langgraph TO lookddak_migration;

ALTER DEFAULT PRIVILEGES FOR ROLE lookddak_ai_app IN SCHEMA public
  GRANT SELECT ON TABLES TO lookddak_migration;
ALTER DEFAULT PRIVILEGES FOR ROLE lookddak_ai_app IN SCHEMA langgraph
  GRANT SELECT ON TABLES TO lookddak_migration;
ALTER DEFAULT PRIVILEGES FOR ROLE lookddak_ai_app IN SCHEMA public
  GRANT SELECT ON SEQUENCES TO lookddak_migration;
ALTER DEFAULT PRIVILEGES FOR ROLE lookddak_ai_app IN SCHEMA langgraph
  GRANT SELECT ON SEQUENCES TO lookddak_migration;
