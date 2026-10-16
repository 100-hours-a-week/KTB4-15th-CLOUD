#!/usr/bin/env python3
"""Prepare disabled Dev PostgreSQL logical-replication subscriptions.

Run on i-0845250822bc61955. No replication slots or workers are started.
The embedded database client runs in the existing FastAPI container.
"""
import argparse, getpass, json, subprocess, sys

CLIENT_CODE = r'''
import json, sys
import psycopg
from psycopg import sql
from psycopg.conninfo import make_conninfo

TABLES = [('public','products'), ('public','usage_amount'), ('public','migration_test_events'), ('langgraph','checkpoint_blobs'), ('langgraph','checkpoint_migrations'), ('langgraph','checkpoint_writes'), ('langgraph','checkpoints')]
FWD_PUB, REV_PUB = 'lookddak_pg_forward_pub', 'lookddak_pg_rollback_pub'
FWD_SUB, REV_SUB = 'lookddak_pg_forward_sub', 'lookddak_pg_rollback_sub'
FWD_SLOT, REV_SLOT = 'lookddak_pg_forward_slot', 'lookddak_pg_rollback_slot'

class PreparationError(Exception):
    pass

def require(value, message):
    if not value:
        raise PreparationError(message)

def protect_logs(conn):
    # These changes apply only to this connection and disappear when it closes.
    for setting,value in [('log_statement','none'),('log_min_duration_statement','-1'),('log_min_duration_sample','-1'),('log_transaction_sample_rate','0'),('log_min_error_statement','panic'),('log_error_verbosity','terse'),('log_parameter_max_length_on_error','0')]:
        actual = conn.execute('SELECT set_config(%s,%s,false)',(setting,value)).fetchone()[0]
        require(actual == value, 'Session logging protection could not be verified')
    libraries = conn.execute('SHOW shared_preload_libraries').fetchone()[0]
    if 'pgaudit' in libraries:
        require(conn.execute("SELECT current_setting('pgaudit.log',true)").fetchone()[0] in (None,'none'), 'Audit logging requires a separate credential-safe procedure')
    if 'pg_stat_statements' in libraries:
        conn.execute("SELECT set_config('pg_stat_statements.track','none',false)")
        require(conn.execute("SHOW pg_stat_statements.track").fetchone()[0] == 'none', 'Query statistics protection failed')

def tables_metadata(conn):
    rows = conn.execute("SELECT n.nspname,c.relname,c.relreplident,c.relrowsecurity,EXISTS(SELECT 1 FROM pg_index i WHERE i.indrelid=c.oid AND i.indisprimary),has_table_privilege('lookddak_migration',c.oid,'SELECT'),has_schema_privilege('lookddak_migration',n.oid,'USAGE') FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN ('public','langgraph') AND c.relkind IN ('r','p') ORDER BY 1,2").fetchall()
    require(sorted((r[0],r[1]) for r in rows) == sorted(TABLES), 'The configured replication table scope has changed')
    for r in rows:
        require(not r[3], 'Row security needs review before replication')
        require(r[4] or r[2] in ('f','i'), 'A table lacks usable replica identity')
        require(r[5] and r[6], 'The migration role lacks SELECT or schema USAGE')
    columns = conn.execute("SELECT n.nspname,c.relname,a.attname,format_type(a.atttypid,a.atttypmod),a.attnotnull,a.attgenerated FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace JOIN pg_attribute a ON a.attrelid=c.oid WHERE n.nspname IN ('public','langgraph') AND c.relkind IN ('r','p') AND a.attnum>0 AND NOT a.attisdropped ORDER BY 1,2,a.attnum").fetchall()
    return rows, columns

def create_publication(conn, name):
    existing = conn.execute('SELECT puballtables,pubinsert,pubupdate,pubdelete,pubtruncate FROM pg_publication WHERE pubname=%s',(name,)).fetchone()
    if existing is None:
        names = sql.SQL(', ').join(sql.SQL('{}.{}').format(sql.Identifier(s),sql.Identifier(t)) for s,t in TABLES)
        conn.execute(sql.SQL('CREATE PUBLICATION {} FOR TABLE {}').format(sql.Identifier(name),names))
        print('PUBLICATION_CREATED=' + name)
    else:
        require(existing == (False,True,True,True,True), 'An existing publication has different options')
        print('PUBLICATION_ALREADY_EXISTS=' + name)
    actual = conn.execute('SELECT schemaname,tablename FROM pg_publication_tables WHERE pubname=%s ORDER BY 1,2',(name,)).fetchall()
    require(sorted(actual) == sorted(TABLES), 'Publication table list differs from the configured tables')

def require_publication(conn, name):
    actual = conn.execute('SELECT schemaname,tablename FROM pg_publication_tables WHERE pubname=%s ORDER BY 1,2',(name,)).fetchall()
    require(sorted(actual) == sorted(TABLES), 'Publication table list differs from the configured tables')

def create_disabled_subscription(conn, name, publication, slot, conninfo, copy_data):
    require(conn.execute("SELECT count(*) FROM pg_subscription WHERE subname=%s AND subdbid=(SELECT oid FROM pg_database WHERE datname=current_database())",(name,)).fetchone()[0] == 0, 'The subscription already exists; use verify instead of recreating it')
    require(conn.execute('SELECT count(*) FROM pg_replication_slots WHERE slot_name=%s',(slot,)).fetchone()[0] == 0, 'Unexpected slot name is already in use')
    statement = sql.SQL("CREATE SUBSCRIPTION {} CONNECTION {} PUBLICATION {} WITH (connect=true, enabled=false, create_slot=false, slot_name={}, copy_data={}, origin='none')").format(sql.Identifier(name),sql.Literal(conninfo),sql.Identifier(publication),sql.Literal(slot),sql.SQL('true' if copy_data else 'false'))
    conn.execute(statement)
    print('DISABLED_SUBSCRIPTION_CREATED=' + name)
    print('PUBLISHER_CONNECTION_SUCCEEDED=' + name)
    row = conn.execute("SELECT subname,subenabled,subslotname,suborigin FROM pg_subscription WHERE subname=%s AND subdbid=(SELECT oid FROM pg_database WHERE datname=current_database())",(name,)).fetchone()
    require(row == (name,False,slot,'none'), 'Subscription options differ from the planned disabled setup')
    relations = conn.execute("SELECT count(*) FROM pg_subscription_rel WHERE srsubid=(SELECT oid FROM pg_subscription WHERE subname=%s AND subdbid=(SELECT oid FROM pg_database WHERE datname=current_database()))",(name,)).fetchone()[0]
    require(relations == len(TABLES), 'Subscription did not register every configured table')
    print('REGISTERED_TABLES=' + str(relations))

def refresh_disabled_subscription(conn, name, publication, slot, copy_data):
    row = conn.execute("SELECT subenabled,subslotname,suborigin,subconninfo FROM pg_subscription WHERE subname=%s AND subdbid=(SELECT oid FROM pg_database WHERE datname=current_database())",(name,)).fetchone()
    require(row is not None, 'The disabled subscription is missing')
    require(row[:3] == (False,slot,'none'), 'Subscription options differ from the planned disabled setup')
    require(conn.execute('SELECT count(*) FROM pg_stat_subscription WHERE subname=%s AND pid IS NOT NULL',(name,)).fetchone()[0] == 0, 'A subscription worker is already running')
    relations = conn.execute("SELECT count(*) FROM pg_subscription_rel WHERE srsubid=(SELECT oid FROM pg_subscription WHERE subname=%s AND subdbid=(SELECT oid FROM pg_database WHERE datname=current_database()))",(name,)).fetchone()[0]
    if relations == len(TABLES):
        print('DISABLED_SUBSCRIPTION_ALREADY_CURRENT=' + name)
        return
    require(relations < len(TABLES), 'The disabled subscription has an unexpected table count')
    conninfo = row[3]
    with psycopg.connect(conninfo,autocommit=True) as publisher:
        require_publication(publisher,publication)
    protect_logs(conn)
    with conn.transaction():
        conn.execute(sql.SQL('ALTER SUBSCRIPTION {} SET (slot_name = NONE)').format(sql.Identifier(name)))
        conn.execute(sql.SQL('DROP SUBSCRIPTION {}').format(sql.Identifier(name)))
        create_disabled_subscription(conn,name,publication,slot,conninfo,copy_data)
    print('DISABLED_SUBSCRIPTION_REFRESHED=' + name)

def report(conn, label):
    for title, query in [
        ('PUBLICATIONS', "SELECT pubname,puballtables FROM pg_publication ORDER BY pubname"),
        ('SUBSCRIPTIONS', "SELECT subname,subenabled,subslotname,suborigin FROM pg_subscription WHERE subdbid=(SELECT oid FROM pg_database WHERE datname=current_database()) ORDER BY subname"),
        ('SLOTS', "SELECT slot_name,database,active,wal_status FROM pg_replication_slots ORDER BY slot_name"),
        ('SUBSCRIPTION_WORKERS', "SELECT subname,pid,relid FROM pg_stat_subscription ORDER BY subname,relid"),
        ('SUBSCRIPTION_TABLES', "SELECT s.subname,n.nspname,c.relname,r.srsubstate FROM pg_subscription_rel r JOIN pg_subscription s ON s.oid=r.srsubid JOIN pg_class c ON c.oid=r.srrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE s.subdbid=(SELECT oid FROM pg_database WHERE datname=current_database()) ORDER BY 1,2,3")
    ]:
        print(label + '_' + title + '=' + json.dumps(conn.execute(query).fetchall(),default=str))

def main(p):
    source = dict(host='postgresql',port=5432,dbname=p['source_db'],user=p['source_user'],password=p['source_password'],connect_timeout=5)
    target = dict(host=p['rds_host'],port=5432,dbname=p['rds_db'],user=p['rds_admin'],password=p['rds_admin_password'],connect_timeout=5,sslmode='require')
    if p['step'] in ('check','verify'):
        source['options'] = '-c default_transaction_read_only=on'
        target['options'] = '-c default_transaction_read_only=on'
    with psycopg.connect(**source,autocommit=True) as ec2, psycopg.connect(**target,autocommit=True) as rds:
        require(ec2.execute('SELECT current_database()').fetchone()[0] == 'lookddak_ai', 'Unexpected EC2 database')
        require(rds.execute('SELECT current_database()').fetchone()[0] == 'lookddak', 'Unexpected RDS database')
        require(ec2.info.server_version >= 160000 and rds.info.server_version >= 160000, 'PostgreSQL 16 or later is required for origin filtering')
        _,source_columns = tables_metadata(ec2)
        _,target_columns = tables_metadata(rds)
        require(source_columns == target_columns, 'Table column definitions differ; inspect before replication')
        for conn in (ec2,rds):
            require(conn.execute('SHOW wal_level').fetchone()[0] == 'logical', 'wal_level is not logical')
            require(conn.execute("SELECT has_database_privilege('lookddak_migration',current_database(),'CONNECT')").fetchone()[0], 'Migration database CONNECT permission is missing')
        counts = [(s+'.'+t,rds.execute(sql.SQL('SELECT count(*) FROM {}.{}').format(sql.Identifier(s),sql.Identifier(t))).fetchone()[0]) for s,t in TABLES]
        print('DATABASES=EC2:lookddak_ai RDS:lookddak')
        print('TABLE_SCOPE_AND_SCHEMA_OK=' + str(len(TABLES)))
        print('RDS_ROW_COUNTS=' + json.dumps(counts))
        print('STEP=' + p['step'],flush=True)
        if p['step'] == 'publications':
            create_publication(ec2,FWD_PUB)
            create_publication(rds,REV_PUB)
        elif p['step'] == 'forward':
            require_publication(ec2,FWD_PUB)
            require(all(count == 0 for _,count in counts), 'RDS already has data; review initial-copy strategy before proceeding')
            # Suppress SQL/error statement logging and query-statistics capture before constructing secret SQL.
            protect_logs(rds)
            params = dict(host='10.30.1.15',port=5432,dbname=p['source_db'],user='lookddak_migration',password=p['source_migration_password'],connect_timeout=5,sslmode='disable',application_name=FWD_SUB,options='-c row_security=off')
            probe_params = dict(params)
            probe_params['options'] = '-c default_transaction_read_only=on -c row_security=off'
            with psycopg.connect(**probe_params,autocommit=True) as probe:
                require(probe.execute('SELECT current_user').fetchone()[0] == 'lookddak_migration','Source credential probe failed')
            create_disabled_subscription(rds,FWD_SUB,FWD_PUB,FWD_SLOT,make_conninfo(**params),True)
            require(ec2.execute('SELECT count(*) FROM pg_replication_slots WHERE slot_name=%s',(FWD_SLOT,)).fetchone()[0] == 0,'Forward slot was unexpectedly created')
        elif p['step'] == 'rollback':
            require_publication(rds,REV_PUB)
            protect_logs(ec2)
            params = dict(host=p['rds_host'],port=5432,dbname=p['rds_db'],user='lookddak_migration',password=p['rds_migration_password'],connect_timeout=5,sslmode='require',application_name=REV_SUB,options='-c row_security=off')
            probe_params = dict(params)
            probe_params['options'] = '-c default_transaction_read_only=on'
            with psycopg.connect(**probe_params,autocommit=True) as probe:
                require(probe.execute("SELECT pg_has_role(current_user,'rds_replication','USAGE')").fetchone()[0],'RDS migration account lacks rds_replication')
            create_disabled_subscription(ec2,REV_SUB,REV_PUB,REV_SLOT,make_conninfo(**params),False)
            require(rds.execute('SELECT count(*) FROM pg_replication_slots WHERE slot_name=%s',(REV_SLOT,)).fetchone()[0] == 0,'Rollback slot was unexpectedly created')
        elif p['step'] == 'refresh-disabled':
            require_publication(ec2,FWD_PUB)
            require_publication(rds,REV_PUB)
            require(ec2.execute('SELECT count(*) FROM pg_replication_slots WHERE slot_name=%s',(FWD_SLOT,)).fetchone()[0] == 0,'Forward slot exists unexpectedly')
            require(rds.execute('SELECT count(*) FROM pg_replication_slots WHERE slot_name=%s',(REV_SLOT,)).fetchone()[0] == 0,'Rollback slot exists unexpectedly')
            refresh_disabled_subscription(rds,FWD_SUB,FWD_PUB,FWD_SLOT,True)
            refresh_disabled_subscription(ec2,REV_SUB,REV_PUB,REV_SLOT,False)
            require(ec2.execute('SELECT count(*) FROM pg_replication_slots WHERE slot_name=%s',(FWD_SLOT,)).fetchone()[0] == 0,'Forward slot was unexpectedly created')
            require(rds.execute('SELECT count(*) FROM pg_replication_slots WHERE slot_name=%s',(REV_SLOT,)).fetchone()[0] == 0,'Rollback slot was unexpectedly created')
        report(ec2,'EC2')
        report(rds,'RDS')
        if p['step'] == 'verify':
            require_publication(ec2,FWD_PUB)
            require_publication(rds,REV_PUB)
            for conn,name,slot in [(rds,FWD_SUB,FWD_SLOT),(ec2,REV_SUB,REV_SLOT)]:
                row=conn.execute("SELECT subenabled,subslotname,suborigin FROM pg_subscription WHERE subname=%s AND subdbid=(SELECT oid FROM pg_database WHERE datname=current_database())",(name,)).fetchone()
                require(row == (False,slot,'none'),'One disabled subscription is missing or has different options')
                require(conn.execute('SELECT count(*) FROM pg_stat_subscription WHERE subname=%s AND pid IS NOT NULL',(name,)).fetchone()[0] == 0,'A subscription worker is already running')
                relations=conn.execute("SELECT count(*) FROM pg_subscription_rel WHERE srsubid=(SELECT oid FROM pg_subscription WHERE subname=%s AND subdbid=(SELECT oid FROM pg_database WHERE datname=current_database()))",(name,)).fetchone()[0]
                require(relations == len(TABLES),'A disabled subscription has not registered every configured table')
            require(ec2.execute('SELECT count(*) FROM pg_replication_slots WHERE slot_name=%s',(FWD_SLOT,)).fetchone()[0] == 0,'Forward slot exists unexpectedly')
            require(rds.execute('SELECT count(*) FROM pg_replication_slots WHERE slot_name=%s',(REV_SLOT,)).fetchone()[0] == 0,'Rollback slot exists unexpectedly')
            print('PREPARATION_COMPLETE_BOTH_SUBSCRIPTIONS_DISABLED')
        print('NO_REPLICATION_STARTED',flush=True)

try:
    main(json.load(sys.stdin))
except PreparationError as e:
    print('STOP=' + str(e),flush=True)
    sys.exit(1)
except Exception as e:
    # SQL text, connection strings and database exception messages may contain credentials.
    print('STOP_DATABASE_ERROR=' + type(e).__name__ + ' SQLSTATE=' + str(getattr(e,'sqlstate',None)),flush=True)
    sys.exit(1)
'''

def call(args):
    result = subprocess.run(args,text=True,capture_output=True)
    if result.returncode:
        raise RuntimeError('Required command failed: ' + ' '.join(args[:3]))
    return result.stdout

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('step',choices=['check','publications','forward','rollback','refresh-disabled','verify'])
    args = parser.parse_args()
    paths = {
        'rds_admin_password':'/lookddak/dev/v2/postgresql/admin/password',
        'rds_admin':'/lookddak/dev/v2/postgresql/admin/username',
        'rds_host':'/lookddak/dev/v2/postgresql/host',
        'rds_db':'/lookddak/dev/v2/postgresql/database'
    }
    if args.step == 'rollback':
        paths['rds_migration_password'] = '/lookddak/dev/v2/postgresql/migration/password'
    raw = json.loads(call(['aws','ssm','get-parameters','--region','ap-northeast-2','--names',*paths.values(),'--with-decryption','--output','json']))
    parameters = {item['Name']:item['Value'] for item in raw['Parameters']}
    missing = [path for key,path in paths.items() if key != 'rds_migration_password' and path not in parameters]
    if missing:
        raise RuntimeError('Required Parameter Store entries are missing: ' + ', '.join(missing))
    postgres = json.loads(call(['docker','inspect','lookddak-postgresql']))[0]
    values = dict(item.split('=',1) for item in postgres['Config']['Env'] if '=' in item)
    payload = {'step':args.step,'source_db':values['POSTGRES_DB'],'source_user':values['POSTGRES_USER'],'source_password':values['POSTGRES_PASSWORD']}
    payload.update({key:parameters[path] for key,path in paths.items() if path in parameters})
    if payload['source_db'] != 'lookddak_ai' or payload['rds_db'] != 'lookddak':
        raise RuntimeError('Unexpected source/target database; stop and inspect')
    if args.step == 'forward':
        if not sys.stdin.isatty():
            raise RuntimeError('Run forward from an interactive EC2 terminal for hidden password entry')
        payload['source_migration_password'] = getpass.getpass('EC2 lookddak_migration password (hidden): ')
        if not payload['source_migration_password']:
            raise RuntimeError('Source migration password is empty')
    if args.step == 'rollback' and 'rds_migration_password' not in payload:
        if not sys.stdin.isatty():
            raise RuntimeError('RDS migration password is not in Parameter Store; run rollback from an interactive EC2 terminal')
        print('RDS migration password is not in Parameter Store; enter the existing RDS account password below.')
        payload['rds_migration_password'] = getpass.getpass('RDS lookddak_migration password (hidden): ')
        if not payload['rds_migration_password']:
            raise RuntimeError('RDS migration password is empty')
    result = subprocess.run(['docker','exec','-i','lookddak-fastapi','python','-c',CLIENT_CODE],input=json.dumps(payload),text=True,capture_output=True,timeout=90)
    print(result.stdout,end='')
    if result.returncode:
        print('STEP_FAILED: inspect the safe STOP message; do not proceed to the next step')
        return 1
    return 0

if __name__ == '__main__':
    try:
        sys.exit(main())
    except RuntimeError as e:
        # These RuntimeErrors are raised by this wrapper with safe messages only.
        print('PREPARATION_HELPER_FAILED=RuntimeError: ' + str(e))
        sys.exit(1)
    except Exception as e:
        print('PREPARATION_HELPER_FAILED=' + type(e).__name__)
        sys.exit(1)
