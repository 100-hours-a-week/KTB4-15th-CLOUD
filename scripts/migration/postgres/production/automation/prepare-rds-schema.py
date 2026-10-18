#!/usr/bin/env python3
"""Prepare and verify the V2 Prod RDS schema without copying application data."""

import argparse
import json
import subprocess
import sys
from pathlib import Path


CLIENT_CODE = r'''
import json
import sys

import psycopg
from psycopg import sql

EXPECTED_TABLES = {
    ('public', 'products'),
    ('public', 'usage_amount'),
    ('public', 'migration_test_events'),
    ('langgraph', 'checkpoint_blobs'),
    ('langgraph', 'checkpoint_migrations'),
    ('langgraph', 'checkpoint_writes'),
    ('langgraph', 'checkpoints'),
}
EXPECTED_WITHOUT_LEDGER = EXPECTED_TABLES - {('public', 'migration_test_events')}
EXPECTED_SEQUENCES = {('public', 'products_id_seq')}


class PreparationError(Exception):
    pass


def require(value, message):
    if not value:
        raise PreparationError(message)


def protect_logs(conn):
    settings = [
        ('log_statement', 'none'),
        ('log_min_duration_statement', '-1'),
        ('log_min_duration_sample', '-1'),
        ('log_transaction_sample_rate', '0'),
        ('log_min_error_statement', 'panic'),
        ('log_error_verbosity', 'terse'),
        ('log_parameter_max_length_on_error', '0'),
    ]
    for name, value in settings:
        conn.execute('SELECT set_config(%s,%s,false)', (name, value))


def table_inventory(conn):
    rows = conn.execute(
        "SELECT schemaname,tablename FROM pg_tables "
        "WHERE schemaname IN ('public','langgraph') ORDER BY 1,2"
    ).fetchall()
    backups = {tuple(row) for row in rows if row[0] == 'public' and row[1].startswith('products_backup_')}
    active = {tuple(row) for row in rows} - backups
    return active, backups


def signature(conn):
    tables, _ = table_inventory(conn)
    require(tables == EXPECTED_TABLES, 'Active table scope differs from the expected seven tables')

    columns = conn.execute(
        "SELECT table_schema,table_name,column_name,ordinal_position,data_type,udt_schema,udt_name,"
        "character_maximum_length,numeric_precision,numeric_scale,is_nullable,column_default,is_identity,is_generated "
        "FROM information_schema.columns WHERE table_schema IN ('public','langgraph') ORDER BY 1,2,4"
    ).fetchall()
    columns = [tuple(row) for row in columns if (row[0], row[1]) in EXPECTED_TABLES]

    constraints = conn.execute(
        "SELECT n.nspname,c.relname,con.conname,con.contype,pg_get_constraintdef(con.oid,true) "
        "FROM pg_constraint con JOIN pg_class c ON c.oid=con.conrelid "
        "JOIN pg_namespace n ON n.oid=c.relnamespace "
        "WHERE n.nspname IN ('public','langgraph') ORDER BY 1,2,3"
    ).fetchall()
    constraints = [tuple(row) for row in constraints if (row[0], row[1]) in EXPECTED_TABLES]

    indexes = conn.execute(
        "SELECT schemaname,tablename,indexname,indexdef FROM pg_indexes "
        "WHERE schemaname IN ('public','langgraph') ORDER BY 1,2,3"
    ).fetchall()
    indexes = [tuple(row) for row in indexes if (row[0], row[1]) in EXPECTED_TABLES]

    sequences = conn.execute(
        "SELECT schemaname,sequencename,data_type,start_value,min_value,max_value,increment_by,cycle,cache_size "
        "FROM pg_sequences WHERE schemaname IN ('public','langgraph') ORDER BY 1,2"
    ).fetchall()
    sequences = [tuple(row) for row in sequences if (row[0], row[1]) in EXPECTED_SEQUENCES]
    require({(row[0], row[1]) for row in sequences} == EXPECTED_SEQUENCES, 'Sequence scope differs')

    ownership = conn.execute(
        "SELECT sn.nspname,s.relname,tn.nspname,t.relname,a.attname "
        "FROM pg_class s JOIN pg_namespace sn ON sn.oid=s.relnamespace "
        "JOIN pg_depend d ON d.objid=s.oid AND d.deptype='a' "
        "JOIN pg_class t ON t.oid=d.refobjid JOIN pg_namespace tn ON tn.oid=t.relnamespace "
        "JOIN pg_attribute a ON a.attrelid=t.oid AND a.attnum=d.refobjsubid "
        "WHERE s.relkind='S' AND sn.nspname IN ('public','langgraph') ORDER BY 1,2"
    ).fetchall()

    return {
        'tables': sorted(tables),
        'columns': columns,
        'constraints': constraints,
        'indexes': indexes,
        'sequences': sequences,
        'ownership': [tuple(row) for row in ownership if (row[0], row[1]) in EXPECTED_SEQUENCES],
    }


def create_source_ledger(conn):
    conn.execute("""
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
    """)


def configure_source_privileges(conn):
    conn.execute('GRANT USAGE ON SCHEMA public, langgraph TO lookddak_app, lookddak_migration')
    conn.execute('GRANT CREATE ON SCHEMA langgraph TO lookddak_app')
    conn.execute('GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public, langgraph TO lookddak_app')
    conn.execute('GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public, langgraph TO lookddak_app')
    conn.execute('GRANT SELECT ON ALL TABLES IN SCHEMA public, langgraph TO lookddak_migration')
    conn.execute('GRANT SELECT ON ALL SEQUENCES IN SCHEMA public, langgraph TO lookddak_migration')
    for schema in ('public', 'langgraph'):
        conn.execute(sql.SQL(
            'ALTER DEFAULT PRIVILEGES FOR ROLE lookddak_ai_app IN SCHEMA {} '
            'GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO lookddak_app'
        ).format(sql.Identifier(schema)))
        conn.execute(sql.SQL(
            'ALTER DEFAULT PRIVILEGES FOR ROLE lookddak_ai_app IN SCHEMA {} '
            'GRANT USAGE, SELECT ON SEQUENCES TO lookddak_app'
        ).format(sql.Identifier(schema)))
        conn.execute(sql.SQL(
            'ALTER DEFAULT PRIVILEGES FOR ROLE lookddak_ai_app IN SCHEMA {} '
            'GRANT SELECT ON TABLES TO lookddak_migration'
        ).format(sql.Identifier(schema)))
        conn.execute(sql.SQL(
            'ALTER DEFAULT PRIVILEGES FOR ROLE lookddak_ai_app IN SCHEMA {} '
            'GRANT SELECT ON SEQUENCES TO lookddak_migration'
        ).format(sql.Identifier(schema)))


def ensure_role(conn, name, password):
    if not conn.execute('SELECT EXISTS(SELECT 1 FROM pg_roles WHERE rolname=%s)', (name,)).fetchone()[0]:
        conn.execute(sql.SQL('CREATE ROLE {} LOGIN').format(sql.Identifier(name)))
    conn.execute(
        sql.SQL('ALTER ROLE {} LOGIN PASSWORD {}').format(sql.Identifier(name), sql.Literal(password))
    )


def configure_target_roles(conn, payload):
    protect_logs(conn)
    ensure_role(conn, 'lookddak_app', payload['rds_app_password'])
    ensure_role(conn, 'lookddak_migration', payload['rds_migration_password'])
    conn.execute('GRANT rds_replication TO lookddak_migration')
    conn.execute('GRANT CONNECT ON DATABASE lookddak TO lookddak_app, lookddak_migration')
    conn.execute('GRANT USAGE ON SCHEMA public, langgraph TO lookddak_app, lookddak_migration')
    conn.execute('GRANT CREATE ON SCHEMA langgraph TO lookddak_app')
    conn.execute('GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public, langgraph TO lookddak_app')
    conn.execute('GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public, langgraph TO lookddak_app')
    conn.execute('GRANT SELECT ON ALL TABLES IN SCHEMA public, langgraph TO lookddak_migration')
    conn.execute('GRANT SELECT ON ALL SEQUENCES IN SCHEMA public, langgraph TO lookddak_migration')
    for schema in ('public', 'langgraph'):
        conn.execute(sql.SQL(
            'ALTER DEFAULT PRIVILEGES FOR ROLE lookddak_admin IN SCHEMA {} '
            'GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO lookddak_app'
        ).format(sql.Identifier(schema)))
        conn.execute(sql.SQL(
            'ALTER DEFAULT PRIVILEGES FOR ROLE lookddak_admin IN SCHEMA {} '
            'GRANT USAGE, SELECT ON SEQUENCES TO lookddak_app'
        ).format(sql.Identifier(schema)))
        conn.execute(sql.SQL(
            'ALTER DEFAULT PRIVILEGES FOR ROLE lookddak_admin IN SCHEMA {} '
            'GRANT SELECT ON TABLES TO lookddak_migration'
        ).format(sql.Identifier(schema)))
        conn.execute(sql.SQL(
            'ALTER DEFAULT PRIVILEGES FOR ROLE lookddak_admin IN SCHEMA {} '
            'GRANT SELECT ON SEQUENCES TO lookddak_migration'
        ).format(sql.Identifier(schema)))


def verify_object_privileges(conn):
    for schema, table in EXPECTED_TABLES:
        qualified = f'{schema}.{table}'
        for privilege in ('SELECT', 'INSERT', 'UPDATE', 'DELETE'):
            require(conn.execute('SELECT has_table_privilege(%s,%s,%s)', ('lookddak_app', qualified, privilege)).fetchone()[0], f'App lacks {privilege} on {qualified}')
        require(conn.execute('SELECT has_table_privilege(%s,%s,%s)', ('lookddak_migration', qualified, 'SELECT')).fetchone()[0], f'Migration role lacks SELECT on {qualified}')
    require(conn.execute("SELECT has_sequence_privilege('lookddak_app','public.products_id_seq','USAGE')").fetchone()[0], 'App lacks sequence USAGE')
    require(conn.execute("SELECT has_sequence_privilege('lookddak_migration','public.products_id_seq','SELECT')").fetchone()[0], 'Migration role lacks sequence SELECT')


def connect_target(payload, user, password, readonly=False):
    kwargs = dict(
        host=payload['rds_host'], port=payload['rds_port'], dbname=payload['rds_db'],
        user=user, password=password, sslmode='require', connect_timeout=5, autocommit=True,
    )
    if readonly:
        kwargs['options'] = '-c default_transaction_read_only=on'
    return psycopg.connect(**kwargs)


def main(payload):
    mode = payload['mode']
    readonly = mode != 'apply'
    source_kwargs = dict(
        host='postgresql', port=5432, dbname=payload['source_db'], user=payload['source_user'],
        password=payload['source_password'], connect_timeout=5, autocommit=True,
    )
    if readonly:
        source_kwargs['options'] = '-c default_transaction_read_only=on'
    with psycopg.connect(**source_kwargs) as source, connect_target(payload, payload['rds_admin'], payload['rds_admin_password'], readonly) as target:
        require(source.execute('SELECT current_database()').fetchone()[0] == 'lookddak_ai', 'Unexpected source database')
        require(target.execute('SELECT current_database()').fetchone()[0] == 'lookddak', 'Unexpected target database')
        source_tables, source_backups = table_inventory(source)
        target_tables, target_backups = table_inventory(target)
        require(not target_backups, 'Backup tables must not exist on RDS')
        require(source_tables in (EXPECTED_WITHOUT_LEDGER, EXPECTED_TABLES), 'Unexpected source application table scope')
        require(target_tables in (set(), EXPECTED_TABLES), 'RDS is neither empty nor fully prepared')
        source_vector = source.execute("SELECT extversion FROM pg_extension WHERE extname='vector'").fetchone()
        target_vector = target.execute("SELECT extversion FROM pg_extension WHERE extname='vector'").fetchone()
        require(source_vector and target_vector, 'pgvector must exist on both databases')
        print('SOURCE_ACTIVE_TABLES=' + str(len(source_tables)))
        print('SOURCE_BACKUP_TABLES_EXCLUDED=' + str(len(source_backups)))
        print('TARGET_TABLES_BEFORE=' + str(len(target_tables)))
        print('PGVECTOR_SOURCE=' + source_vector[0] + ' TARGET=' + target_vector[0])

        if mode == 'check':
            print('SCHEMA_PRECHECK=ready')
            print('NO_DATA_COPIED')
            return

        if mode == 'apply':
            if source_tables == EXPECTED_WITHOUT_LEDGER:
                with source.transaction():
                    create_source_ledger(source)
                print('SOURCE_LEDGER_TABLE_CREATED=true')
            else:
                print('SOURCE_LEDGER_TABLE_ALREADY_EXISTS=true')

            with source.transaction():
                configure_source_privileges(source)
            print('SOURCE_PRIVILEGES_CONFIGURED=true')

            if not target_tables:
                with target.transaction():
                    target.execute(payload['schema_sql'])
                print('TARGET_SCHEMA_CREATED=true')
            else:
                print('TARGET_SCHEMA_ALREADY_EXISTS=true')

            with target.transaction():
                configure_target_roles(target, payload)
            print('TARGET_ROLES_CONFIGURED=true')

        source_signature = signature(source)
        target_signature = signature(target)
        require(source_signature == target_signature, 'V1 and V2 schema signatures differ')
        verify_object_privileges(source)
        verify_object_privileges(target)
        require(source.execute("SELECT rolreplication FROM pg_roles WHERE rolname='lookddak_migration'").fetchone()[0], 'EC2 migration role lacks REPLICATION')
        require(target.execute("SELECT pg_has_role('lookddak_migration','rds_replication','MEMBER')").fetchone()[0], 'RDS migration role lacks rds_replication')

        target_rows = 0
        for schema, table in EXPECTED_TABLES:
            target_rows += target.execute(
                sql.SQL('SELECT count(*) FROM {}.{}').format(sql.Identifier(schema), sql.Identifier(table))
            ).fetchone()[0]
        require(target_rows == 0, 'RDS tables must remain empty before initial logical replication copy')

        with connect_target(payload, 'lookddak_app', payload['rds_app_password'], True) as app:
            require(app.execute('SELECT current_user').fetchone()[0] == 'lookddak_app', 'App login failed')
            app.execute('SELECT count(*) FROM public.products').fetchone()
        with connect_target(payload, 'lookddak_migration', payload['rds_migration_password'], True) as migration:
            require(migration.execute('SELECT current_user').fetchone()[0] == 'lookddak_migration', 'Migration login failed')
            migration.execute('SELECT count(*) FROM public.products').fetchone()

        print('SCHEMA_COMPARE=match')
        print('TARGET_TABLES=' + str(len(EXPECTED_TABLES)))
        print('TARGET_SEQUENCES=' + str(len(EXPECTED_SEQUENCES)))
        print('TARGET_ROW_COUNT=0')
        print('SOURCE_OBJECT_PRIVILEGES=verified')
        print('APP_ROLE_LOGIN_AND_PRIVILEGES=verified')
        print('MIGRATION_ROLE_LOGIN_AND_PRIVILEGES=verified')
        print('NO_REPLICATION_STARTED')


try:
    main(json.load(sys.stdin))
except PreparationError as exc:
    print('STOP=' + str(exc), flush=True)
    sys.exit(1)
except Exception as exc:
    print('STOP_DATABASE_ERROR=' + type(exc).__name__ + ' SQLSTATE=' + str(getattr(exc, 'sqlstate', None)), flush=True)
    sys.exit(1)
'''


def call(args):
    result = subprocess.run(args, text=True, capture_output=True)
    if result.returncode:
        raise RuntimeError('Required command failed: ' + ' '.join(args[:3]))
    return result.stdout


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=['check', 'apply', 'verify'])
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    schema_sql = (root / 'sql' / 'setup-rds-schema.sql').read_text(encoding='utf-8')

    paths = {
        'rds_admin_password': '/lookddak/prod/v2/postgresql/admin/password',
        'rds_admin': '/lookddak/prod/v2/postgresql/admin/username',
        'rds_host': '/lookddak/prod/v2/postgresql/host',
        'rds_port': '/lookddak/prod/v2/postgresql/port',
        'rds_db': '/lookddak/prod/v2/postgresql/database',
        'rds_app_password': '/lookddak/prod/v2/postgresql/app/password',
        'rds_migration_password': '/lookddak/prod/v2/postgresql/migration/password',
    }
    raw = json.loads(call([
        'aws', 'ssm', 'get-parameters', '--region', 'ap-northeast-2', '--names',
        *paths.values(), '--with-decryption', '--output', 'json',
    ]))
    parameters = {item['Name']: item['Value'] for item in raw['Parameters']}
    missing = [path for path in paths.values() if path not in parameters]
    if missing:
        raise RuntimeError('Required Parameter Store entries are missing: ' + ', '.join(missing))

    postgres = json.loads(call(['docker', 'inspect', 'lookddak-postgresql']))[0]
    values = dict(item.split('=', 1) for item in postgres['Config']['Env'] if '=' in item)
    payload = {
        'mode': args.mode,
        'schema_sql': schema_sql,
        'source_db': values['POSTGRES_DB'],
        'source_user': values['POSTGRES_USER'],
        'source_password': values['POSTGRES_PASSWORD'],
    }
    payload.update({name: parameters[path] for name, path in paths.items()})
    if payload['source_db'] != 'lookddak_ai' or payload['rds_db'] != 'lookddak':
        raise RuntimeError('Unexpected source or target database')
    if payload['rds_admin'] != 'lookddak_admin':
        raise RuntimeError('Unexpected RDS administrator account')

    result = subprocess.run(
        ['docker', 'exec', '-i', 'lookddak-fastapi', 'python', '-c', CLIENT_CODE],
        input=json.dumps(payload), text=True, capture_output=True, timeout=180,
    )
    print(result.stdout, end='')
    if result.returncode:
        print('SCHEMA_PREPARATION_FAILED: inspect the safe STOP message')
        return 1
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except RuntimeError as exc:
        print('SCHEMA_HELPER_FAILED=RuntimeError: ' + str(exc))
        sys.exit(1)
    except Exception as exc:
        print('SCHEMA_HELPER_FAILED=' + type(exc).__name__)
        sys.exit(1)
