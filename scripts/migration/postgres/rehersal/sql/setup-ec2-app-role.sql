\set ON_ERROR_STOP on
\getenv lookddak_app_password LOOKDDAK_APP_PASSWORD

DO $role$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'lookddak_app') THEN
    CREATE ROLE lookddak_app LOGIN;
  END IF;
END
$role$;

ALTER ROLE lookddak_app LOGIN PASSWORD :'lookddak_app_password';

GRANT CONNECT ON DATABASE lookddak_ai TO lookddak_app;
GRANT USAGE ON SCHEMA public, langgraph TO lookddak_app;
GRANT CREATE ON SCHEMA langgraph TO lookddak_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public, langgraph TO lookddak_app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public, langgraph TO lookddak_app;

ALTER DEFAULT PRIVILEGES FOR ROLE lookddak_ai_app IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO lookddak_app;
ALTER DEFAULT PRIVILEGES FOR ROLE lookddak_ai_app IN SCHEMA langgraph
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO lookddak_app;
ALTER DEFAULT PRIVILEGES FOR ROLE lookddak_ai_app IN SCHEMA public
  GRANT USAGE, SELECT ON SEQUENCES TO lookddak_app;
ALTER DEFAULT PRIVILEGES FOR ROLE lookddak_ai_app IN SCHEMA langgraph
  GRANT USAGE, SELECT ON SEQUENCES TO lookddak_app;
