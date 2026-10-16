#!/usr/bin/env bash
# Commands are run by the operator on Dev EC2. No passwords are written to files.
set -Eeuo pipefail
set +x
MODE=${1:-help}
RUN_ID=${2:-}
[[ "$RUN_ID" =~ ^[A-Za-z0-9_-]+$ ]] || { echo 'Usage: bash r1-3-tools.sh {start|status|rollback|finish} <new-run-id>'; exit 2; }
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
RESULT="$ROOT/results/$RUN_ID"
DB_RUN_ID="$RUN_ID-live"
REGION=${AWS_REGION:-ap-northeast-2}
FWD=lookddak_pg_forward_sub
REV=lookddak_pg_rollback_sub
FSLOT=lookddak_pg_forward_slot
RSLOT=lookddak_pg_rollback_slot
PGBDIR=/opt/lookddak/pgbouncer
case "$MODE" in start|status|rollback|finish) ;; *) echo 'Unknown mode'; exit 2;; esac
sudo mkdir -p "$RESULT"
exec > >(sudo tee -a "$RESULT/tools-$MODE-$(date -u +%Y%m%dT%H%M%SZ).log") 2>&1
if [[ "$MODE" != status ]]; then exec 9>/tmp/lookddak-postgresql-switchover.lock; flock -n 9 || { echo 'STOP=another rehearsal command is running'; exit 1; }; fi
ssm() { aws ssm get-parameter --region "$REGION" --name "/lookddak/dev/v2/postgresql/$1" --with-decryption --query Parameter.Value --output text; }
RDS_HOST=$(ssm host)
RDS_PORT=$(ssm port)
RDS_DB=$(ssm database)
RDS_ADMIN=$(ssm admin/username)
RDS_ADMIN_PASSWORD=$(ssm admin/password)
APP_PASSWORD=$(ssm app/password)
[[ -n "$RDS_ADMIN_PASSWORD" && -n "$APP_PASSWORD" ]]
RDS_DSN="host=$RDS_HOST port=$RDS_PORT dbname=$RDS_DB user=$RDS_ADMIN sslmode=require connect_timeout=3"
trap 'unset RDS_ADMIN_PASSWORD APP_PASSWORD' EXIT
ec2sql() { timeout --foreground 8 sudo docker exec -i -e 'PGOPTIONS=-c statement_timeout=5000 -c lock_timeout=3000' lookddak-postgresql psql -X -v ON_ERROR_STOP=1 -U lookddak_ai_app -d lookddak_ai "$@"; }
rdssql() { timeout --foreground 8 sudo docker exec -i -e PGPASSWORD="$RDS_ADMIN_PASSWORD" -e 'PGOPTIONS=-c statement_timeout=5000 -c lock_timeout=3000' lookddak-pgbench psql -X -v ON_ERROR_STOP=1 "$RDS_DSN" "$@"; }
ec2snapshot() { timeout --foreground 20 sudo docker exec -i -e 'PGOPTIONS=-c statement_timeout=15000 -c lock_timeout=3000' lookddak-postgresql psql -X -v ON_ERROR_STOP=1 -U lookddak_ai_app -d lookddak_ai "$@"; }
rdssnapshot() { timeout --foreground 20 sudo docker exec -i -e PGPASSWORD="$RDS_ADMIN_PASSWORD" -e 'PGOPTIONS=-c statement_timeout=15000 -c lock_timeout=3000' lookddak-pgbench psql -X -v ON_ERROR_STOP=1 "$RDS_DSN" "$@"; }
pgb() { timeout --foreground 12 sudo docker exec lookddak-pgbouncer psql -X -v ON_ERROR_STOP=1 -h /var/run/pgbouncer -p 6432 -U pgbouncer_admin -d pgbouncer -c "$1"; }
backend() { pgb 'SHOW DATABASES;' | awk -F'|' 'BEGIN{FS="[|]"} /lookddak_ai/ {gsub(/ /, ""); print $2 "|" $3 "|" $4 "|" $5}'; }
app_backend() { timeout --foreground 8 sudo docker exec -e PGPASSWORD="$APP_PASSWORD" lookddak-pgbench psql -X -v ON_ERROR_STOP=1 'host=pgbouncer port=6432 dbname=lookddak_ai user=lookddak_app connect_timeout=3' -Atc "SELECT current_database()||'|'||current_user||'|'||inet_server_port();"; }
die() { echo "STOP=$*" >&2; return 1; }
check_directions() {
  [[ "$(rdssql -Atc "SELECT subenabled::text||'|'||suborigin FROM pg_subscription WHERE subname='$FWD';")" = "$1|none" ]] || die 'unexpected forward subscription state/origin';
  [[ "$(ec2sql -Atc "SELECT subenabled::text||'|'||suborigin FROM pg_subscription WHERE subname='$REV';")" = "$2|none" ]] || die 'unexpected reverse subscription state/origin';
}
alive() { sudo docker exec lookddak-pgbench sh -c 'pid=$(cat "/results/$1/pgbench-live.pid") && kill -0 "$pid" 2>/dev/null && [ "$(cat /proc/$pid/comm)" = pgbench ]' sh "$RUN_ID"; }
client_fingerprints() {
  pgb 'SHOW CLIENTS;' | awk -F'|' '
    NR==1 { for(i=1;i<=NF;i++){gsub(/^ +| +$/, "", $i); col[$i]=i} }
    /lookddak-pgbench/ { keys[1]="user";keys[2]="database";keys[3]="addr";keys[4]="port";keys[5]="connect_time";keys[6]="ptr";
      for(i=1;i<=6;i++){v=$(col[keys[i]]);gsub(/^ +| +$/, "",v);printf "%s%s",(i==1?"":"|"),v} print "" }
  ' | sort
}
wait_slot() {
  local side=$1 slot=$2 wanted=$3 value
  for _ in {1..10}; do
    value=$("${side}sql" -Atc "SELECT COALESCE((SELECT active::text FROM pg_replication_slots WHERE slot_name='$slot'),'missing');")
    [[ "$value" = "$wanted" ]] && return 0
    [[ ${PAUSED:-0} = 0 ]] || budget
    sleep 0.5
  done
  die "slot $slot did not become $wanted (last=$value)"
}
wait_catchup() {
  local side=$1 slot=$2 target
  target=$("${side}sql" -Atc 'SELECT pg_current_wal_lsn();')
  for _ in {1..20}; do
    if [[ $("${side}sql" -Atc "SELECT COALESCE((SELECT confirmed_flush_lsn >= '$target'::pg_lsn FROM pg_replication_slots WHERE slot_name='$slot'),false)::text;") = true ]]; then
      echo "CAUGHT_UP side=$side target_lsn=$target"; return 0
    fi
    budget
    sleep 0.5
  done
  die "subscriber did not confirm target $target"
}
budget() { (( SECONDS - PAUSE_START <= 25 )) || die 'PAUSE exceeded 25s budget'; }
sync_sequence() {
  local from=$1 to=$2 value called
  IFS='|' read -r value called <<< "$("${from}sql" -Atc 'SELECT last_value,is_called FROM public.products_id_seq;')"
  [[ "$value" =~ ^[0-9]+$ && "$called" =~ ^[tf]$ ]] || die 'unexpected sequence value'
  "${to}sql" -Atc "SELECT setval('public.products_id_seq',$value,'$called'::boolean);" >/dev/null
  echo "SEQUENCE_SYNCED from=$from to=$to value=$value is_called=$called"
}
snapshot() {
  ec2snapshot -v run_id="$DB_RUN_ID" < "$ROOT/sql/data-consistency-r1-3.sql" | sudo tee "$RESULT/consistency-ec2.txt" >/dev/null
  budget
  rdssnapshot -v run_id="$DB_RUN_ID" < "$ROOT/sql/data-consistency-r1-3.sql" | sudo tee "$RESULT/consistency-rds.txt" >/dev/null
  budget
  if ! sudo diff -u "$RESULT/consistency-ec2.txt" "$RESULT/consistency-rds.txt" > /tmp/"$RUN_ID"-consistency.diff; then
    sudo cp /tmp/"$RUN_ID"-consistency.diff "$RESULT/consistency.diff"
    die "data mismatch: $RESULT/consistency.diff"
  fi
  echo 'CONSISTENCY_OK=7 tables and event IDs/checksums match'
  sudo awk -F'|' '$1=="LEDGER_SUMMARY" || $1=="TABLE_CHECKSUM"' "$RESULT/consistency-ec2.txt"
}
show_status() {
  date -u +STATUS_UTC=%Y-%m-%dT%H:%M:%SZ
  pgb 'SHOW DATABASES;'
  pgb 'SHOW CLIENTS;'
  app_backend
  if alive; then echo 'PGBENCH_ALIVE=true'; else echo 'PGBENCH_ALIVE=false'; fi
  if alive && sudo test -f "$RESULT/pgbench-clients-original.txt"; then
    client_fingerprints | sudo tee "$RESULT/pgbench-clients-latest.txt" >/dev/null
    if sudo diff -q "$RESULT/pgbench-clients-original.txt" "$RESULT/pgbench-clients-latest.txt" >/dev/null; then echo 'PGBENCH_CLIENTS_UNCHANGED=true'; else echo 'PGBENCH_CLIENTS_UNCHANGED=false'; fi
  fi
  sudo tail -n 8 "$RESULT/pgbench-live.log"
  for side in ec2 rds; do
    echo "DB=$side"
    "${side}sql" -c "SELECT subname,subenabled,suborigin FROM pg_subscription; SELECT slot_name,active,wal_status,pg_wal_lsn_diff(pg_current_wal_lsn(),confirmed_flush_lsn) AS lag_bytes FROM pg_replication_slots WHERE slot_type='logical'; SELECT subname,apply_error_count,sync_error_count FROM pg_stat_subscription_stats; SELECT count(*) AS events,count(DISTINCT event_id) AS unique_events FROM public.migration_test_events WHERE run_id='$DB_RUN_ID'; SELECT client_id,count(*),max(event_no) FROM public.migration_test_events WHERE run_id='$DB_RUN_ID' GROUP BY client_id ORDER BY client_id;"
  done
}
if [[ "$MODE" = status ]]; then show_status; exit; fi
if [[ "$MODE" = start ]]; then
  check_directions true false
  [[ "$(backend)" = 'postgresql|5432|lookddak_ai|' ]] || die 'PgBouncer is not using EC2 without a forced user'
  [[ $(app_backend) = 'lookddak_ai|lookddak_app|5432' ]] || die 'common application login failed'
  [[ $(ec2sql -Atc "SELECT count(*) FROM public.migration_test_events WHERE run_id='$DB_RUN_ID';") = 0 ]] || die 'run ID already has rows; use a new ID'
  sudo test ! -e "$RESULT/pgbench-live.pid" || die 'run ID already used; do not overwrite or restart'
  sudo docker exec lookddak-pgbench sh -c 'for p in /proc/[0-9]*/comm; do [ "$(cat "$p" 2>/dev/null)" != pgbench ] || exit 1; done' || die 'an earlier pgbench process is still running'
  printf '%s\n' "$APP_PASSWORD" | sudo docker exec -i lookddak-pgbench sh -c '
    IFS= read -r PGPASSWORD; export PGPASSWORD
    export PGHOST=pgbouncer PGPORT=6432 PGDATABASE=lookddak_ai PGUSER=lookddak_app PGAPPNAME=lookddak-pgbench
    mkdir -p "/results/$1"
    nohup sh -c '\''
      pgbench -n -M simple -c 4 -j 2 -R 30 -L 5000 -T 600 -P 5 --progress-timestamp -l --log-prefix="/results/$1/pgbench-tx" -f /scripts/ledger-r1-3.sql -D "run_id=$2" -D source_label=via_pgbouncer -D client_event_no=0 -D hold_sec=0 &
      pid=$!; printf "%s\n" "$pid" > "/results/$1/pgbench-live.pid"
      wait "$pid"; rc=$?; printf "%s\n" "$rc" > "/results/$1/pgbench-live.exit"; exit "$rc"
    '\'' sh "$1" "$2" > "/results/$1/pgbench-live.log" 2>&1 < /dev/null &
  ' sh "$RUN_ID" "$DB_RUN_ID"
  sleep 2
  alive || die 'pgbench startup failed; inspect pgbench-live.log'
  pgb 'SHOW CLIENTS;' | sudo tee "$RESULT/clients-before-switch.txt"
  client_fingerprints | sudo tee "$RESULT/pgbench-clients-original.txt" >/dev/null
  [[ $(sudo awk 'END { print NR }' "$RESULT/pgbench-clients-original.txt") -eq 4 ]] || die 'expected 4 pgbench client connections'
  echo "PGBENCH_STARTED=4 persistent clients, 30 TPS total, 600s; run_id=$DB_RUN_ID"
  exit
fi

PAUSED=0
EC2_MAY_HAVE_WRITES=0
RECOVERY_FAILED=0
recover() {
  local rc=$?
  trap - ERR INT TERM
  set +e
  echo "COMMAND_FAILED mode=$MODE exit_code=$rc"
  if [[ "$MODE" = rollback && "$PAUSED" = 1 && "$EC2_MAY_HAVE_WRITES" = 0 ]]; then
    # RDS is still the writer. The reverse slot is retained until rollback succeeds.
    rdssql -c "ALTER SUBSCRIPTION $FWD DISABLE;" || RECOVERY_FAILED=1
    wait_slot ec2 "$FSLOT" false || RECOVERY_FAILED=1
    ec2sql -c "ALTER SUBSCRIPTION $REV ENABLE;" || RECOVERY_FAILED=1
    sudo sh -c 'cat "$1" > "$2"' sh "$PGBDIR/pgbouncer.rds.ini" "$PGBDIR/pgbouncer.ini" || RECOVERY_FAILED=1
    pgb 'RELOAD;' || RECOVERY_FAILED=1
    pgb 'RECONNECT lookddak_ai;' || RECOVERY_FAILED=1
    pgb 'RESUME lookddak_ai;' || RECOVERY_FAILED=1
    echo "FAILSAFE=RDS path restoration attempted; recovery_errors=$RECOVERY_FAILED; verify with status"
  elif [[ "$PAUSED" = 1 ]]; then
    pgb 'RESUME lookddak_ai;' || RECOVERY_FAILED=1
    echo "FAILSAFE=EC2 path retained; resume attempted; recovery_errors=$RECOVERY_FAILED; verify with status"
  else
    echo 'FAILSAFE=current database path retained; verify with status'
  fi
  exit "$((rc == 0 ? 1 : rc))"
}
trap recover ERR INT TERM
if [[ "$MODE" = rollback ]]; then
  check_directions false true
  [[ "$(backend)" = "$RDS_HOST|$RDS_PORT|$RDS_DB|" ]] || die 'PgBouncer is not on RDS without a forced user'
  ORIGINAL_PGBENCH_RUNNING=0
  if alive; then ORIGINAL_PGBENCH_RUNNING=1; else echo 'CONTINUITY_FAILED=original pgbench is not running; proceeding only to recover EC2 safely'; fi
  wait_slot ec2 "$FSLOT" false
  wait_slot rds "$RSLOT" true
  PAUSE_START=$SECONDS; PAUSED=1
  echo "ROLLBACK_PAUSE_UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  pgb 'PAUSE lookddak_ai;' >/dev/null
  wait_catchup rds "$RSLOT"
  # Freeze the writer before comparing the event set; application writes must use PgBouncer.
  SUMMARY_SQL="SET TIME ZONE 'UTC'; SELECT count(*),count(DISTINCT event_id),md5(COALESCE(string_agg(md5(row_to_json(t)::text),'' ORDER BY event_id),'')) FROM public.migration_test_events t WHERE run_id='$DB_RUN_ID';"
  RDS_EVENTS=$(rdssql -qAtc "$SUMMARY_SQL")
  EC2_EVENTS=$(ec2sql -qAtc "$SUMMARY_SQL")
  [[ "$RDS_EVENTS" = "$EC2_EVENTS" ]] || die 'reverse event data mismatch; retaining RDS as writer'
  echo "REVERSE_EVENT_SET_OK=$RDS_EVENTS"
  sync_sequence rds ec2
  budget
  ec2sql -c "ALTER SUBSCRIPTION $REV DISABLE;" >/dev/null
  wait_slot rds "$RSLOT" false
  rdssql -c "ALTER SUBSCRIPTION $FWD ENABLE;" >/dev/null
  wait_slot ec2 "$FSLOT" true
  budget
  sudo sh -c 'cat "$1" > "$2"' sh "$PGBDIR/pgbouncer.ec2.ini" "$PGBDIR/pgbouncer.ini"
  pgb 'RELOAD;' >/dev/null
  pgb 'RECONNECT lookddak_ai;' >/dev/null
  budget
  [[ "$(backend)" = 'postgresql|5432|lookddak_ai|' ]] || die 'EC2 PgBouncer target mismatch'
  EC2_MAY_HAVE_WRITES=1
  pgb 'RESUME lookddak_ai;' >/dev/null
  PAUSED=0
  echo "ROLLBACK_RESUME_UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ) pause_seconds=$((SECONDS-PAUSE_START))"
  [[ $(app_backend) = 'lookddak_ai|lookddak_app|5432' ]] || die 'EC2 application connection failed'
  sleep 15
  if [[ "$ORIGINAL_PGBENCH_RUNNING" = 1 ]]; then alive || die 'pgbench stopped after rollback; retaining EC2 path'; fi
  if alive; then
    client_fingerprints | sudo tee "$RESULT/pgbench-clients-after-rollback.txt" >/dev/null
    sudo diff -q "$RESULT/pgbench-clients-original.txt" "$RESULT/pgbench-clients-after-rollback.txt" >/dev/null || die 'pgbench client connections changed during rehearsal'
    echo 'PGBENCH_CLIENTS_UNCHANGED=true'
  fi
  if sudo grep -Eiq 'FATAL:|ERROR:|Run was aborted|connection .* failed|timeout expired|client .*aborted' "$RESULT/pgbench-live.log"; then die 'pgbench contains errors'; fi
  check_directions true false
  # Only the now-unused reverse slot is removed; the forward slot stays for replication.
  rdssql -Atc "SELECT pg_drop_replication_slot('$RSLOT');" >/dev/null
  echo 'ROLLBACK_TO_EC2_SUCCEEDED forward=true reverse=false reverse_slot=removed'
  exit
fi

# finish: run after the timed pgbench workload has ended, while the service uses EC2.
check_directions true false
[[ "$(backend)" = 'postgresql|5432|lookddak_ai|' ]] || die 'finish requires the EC2 service path'
if alive; then die 'pgbench is still running (600s). Wait for its normal completion, then run finish again'; fi
[[ $(sudo cat "$RESULT/pgbench-live.exit") = 0 ]] || die 'pgbench did not complete normally'
if sudo grep -Eiq 'FATAL:|ERROR:|Run was aborted|connection .* failed|timeout expired|client .*aborted' "$RESULT/pgbench-live.log"; then die 'pgbench contains errors'; fi
PROCESSED=$(sudo awk '/^number of transactions actually processed:/ {split($NF,a,"/");print a[1]}' "$RESULT/pgbench-live.log")
[[ "$PROCESSED" =~ ^[1-9][0-9]*$ ]] || die 'pgbench summary missing'
sudo grep -Eq '^number of failed transactions: 0([ /]|$)' "$RESULT/pgbench-live.log" || die 'failed transaction count is nonzero or missing'
if sudo grep -Eq '^(number of )?transactions skipped: [1-9]' "$RESULT/pgbench-live.log"; then die 'pgbench skipped transactions'; fi
PAUSE_START=$SECONDS; PAUSED=1
pgb 'PAUSE lookddak_ai;' >/dev/null
wait_catchup ec2 "$FSLOT"
sync_sequence ec2 rds
snapshot
ROWS=$(ec2sql -Atc "SELECT count(*) FROM public.migration_test_events WHERE run_id='$DB_RUN_ID';")
[[ "$ROWS" = "$PROCESSED" ]] || die "committed rows=$ROWS differ from pgbench successes=$PROCESSED"
TX_STATS=$(sudo docker exec lookddak-pgbench sh -c 'awk '\''$3 ~ /^[0-9]+$/ {n++; if ($3>m) m=$3} END {printf "%d|%.3f",n,m/1000}'\'' /results/"$1"/pgbench-tx.*' sh "$RUN_ID")
[[ "${TX_STATS%%|*}" = "$PROCESSED" ]] || die 'successful transaction log count does not match pgbench summary'
EC2_SEQ=$(ec2sql -Atc 'SELECT last_value,is_called FROM public.products_id_seq;')
RDS_SEQ=$(rdssql -Atc 'SELECT last_value,is_called FROM public.products_id_seq;')
[[ "$EC2_SEQ" = "$RDS_SEQ" ]] || die "sequences differ: ec2=$EC2_SEQ rds=$RDS_SEQ"
budget
pgb 'RESUME lookddak_ai;' >/dev/null
PAUSED=0
echo "FINAL_DATA_OK rows=$ROWS pgbench_successes=$PROCESSED seq=$EC2_SEQ"
echo "PGBENCH_TRANSACTION_LOG_STATS successful_tx=${TX_STATS%%|*} max_latency_ms=${TX_STATS#*|}"
echo "FINAL_VERIFY_PAUSE_SECONDS=$((SECONDS-PAUSE_START))"
for c in lookddak-postgresql lookddak-pgbouncer lookddak-pgbench lookddak-fastapi lookddak-nginx; do sudo docker inspect -f '{{.Name}} {{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$c"; done
echo 'FINISH_COMPLETE=EC2 path; forward replication remains enabled; assess k6 and client continuity before declaring R1 pass'
