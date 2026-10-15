#!/usr/bin/env bash
# EC2 배치 경로: /opt/lookddak/v1-mysql-migration/observe.sh
# 사용법:
#   수집: sudo ./observe.sh <dev|prod> <구 DB 엔드포인트> <신 DB 엔드포인트> [간격초=1]   (Ctrl+C로 종료)
#   요약: ./observe.sh report <CSV 파일>
#
# 역할: 전환·부하 리허설 동안 ProxySQL과 두 DB 상태를 1초마다 CSV로 남긴다. (조회만 함)
#   CloudWatch(1분)로는 약 4초짜리 전환을 볼 수 없고, 외부 복제는 RDS ReplicaLag 지표에도 잡히지 않는다.
#
# 기록 항목 (시각은 UTC, cutover.sh 로그·k6 결과와 초 단위로 맞춰 본다)
#   ProxySQL : ONLINE 서버, 서버별 상태·ConnUsed·ConnFree·Queries, 누적 에러 수,
#              클라이언트 연결 수, Questions, 백엔드 연결 획득 실패 수
#   두 DB    : read_only, 앱 연결 수, Com_insert/update/delete(누적), binlog 위치,
#              복제 원본·IO/SQL 스레드·지연·적용 위치(Exec)·복제 에러
#
# report가 짚는 것
#   - 쓰기 대상(ProxySQL ONLINE)과 복제 방향이 바뀐 시점
#   - ProxySQL 에러·연결 획득 실패 증가
#   - 복제 에러, 스레드 중단, 지연 > 2초
#   - 쓰기 대상이 아닌 DB의 앱 연결 (split-brain 신호)
#     앱 연결 = 관리자·repl·rdsadmin·event_scheduler·system user·unauthenticated user를 뺀 연결.
#     unauthenticated user는 인증(TLS 핸드셰이크) 중인 새 연결로, verify-sync.sh 등 관리 스크립트가
#     연결을 여는 순간 잠깐 보이므로 앱 연결로 세지 않는다.
#   - 쓰기 대상이 아닌 DB의 Com_insert/update/delete 증가 (보조 신호)
#     복제로 적용한 쓰기도 레플리카의 Com_*에 잡히므로(2026-10-15 부하 기준 측정에서 확인),
#     쓰기 대상을 복제 중(원본 = 쓰기 대상, IO·SQL Yes)인 동안의 증가는 세지 않는다.
#     그 밖의 증가는 연속 구간으로 묶어 출력한다. rds_* 프로시저([6]·[7]), RDS 내부 작업도 잡힐 수 있다.
#   - 수집을 Ctrl+C로 멈출 때 기록 중이던 샘플은 버린다. 열 개수가 맞지 않는 줄은 report에서 건너뛴다.

set -Euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

report() {
  local csv="$1"
  [[ -f "$csv" ]] || { echo "CSV 없음: $csv"; exit 64; }
  python3 - "$csv" <<'PY'
import csv, sys
all_rows = list(csv.DictReader(open(sys.argv[1])))
rows = [r for r in all_rows if None not in r and None not in r.values()]
skipped = len(all_rows) - len(rows)
if not rows:
    print("기록 없음"); sys.exit(0)
old, new = rows[0]["old_host"], rows[0]["new_host"]
name = {old: "구 DB", new: "신 DB", "": "(없음)"}
events = []
prev = None
max_lag = {"old": 0, "new": 0}
streak = {"old": None, "new": None}
com = {"old": None, "new": None}   # [시작, 끝, 합계] 연속 증가 구간

def flush_com(side):
    if com[side]:
        a, b, total = com[side]
        span = a if a == b else f"{a}~{b}"
        events.append((a, f"? 쓰기 대상이 아닌 {name[old if side == 'old' else new]} Com_insert/update/delete +{total} ({span}, 복제 외 쓰기. 앱 연결 0이면 rds_* 프로시저·RDS 내부 작업일 수 있음)"))
        com[side] = None
for r in rows:
    t = r["ts_utc"]
    writer = r["proxy_online"]
    if prev is None or writer != prev["proxy_online"]:
        events.append((t, f"ProxySQL 쓰기 대상: {name.get(writer, writer or '(없음)')}  pool={r['proxy_pool']}"))
    elif r["proxy_pool"].split(";")[0:2] != prev["proxy_pool"].split(";")[0:2] and any(s in r["proxy_pool"] for s in ("OFFLINE_SOFT", "OFFLINE_HARD")):
        events.append((t, f"ProxySQL pool 상태: {r['proxy_pool']}"))
    if prev:
        for k, label in (("proxy_err_total", "ProxySQL 에러"), ("connpool_get_fail", "백엔드 연결 획득 실패")):
            try:
                d = int(r[k] or 0) - int(prev[k] or 0)
            except ValueError:
                d = 0
            if d > 0:
                events.append((t, f"{label} +{d} (누적 {r[k]})"))
    for side in ("old", "new"):
        host = old if side == "old" else new
        label = name[host]
        repl = (r[f"{side}_src"], r[f"{side}_io"], r[f"{side}_sql"])
        if prev is None or repl != (prev[f"{side}_src"], prev[f"{side}_io"], prev[f"{side}_sql"]):
            src = name.get(r[f"{side}_src"], r[f"{side}_src"]) if r[f"{side}_src"] else "없음"
            events.append((t, f"{label} 복제: 원본={src} IO={r[f'{side}_io'] or '-'} SQL={r[f'{side}_sql'] or '-'} 적용={r[f'{side}_exec']}"))
        err = r[f"{side}_err"]
        if err and (prev is None or err != prev[f"{side}_err"]):
            events.append((t, f"!! {label} 복제 에러: {err}"))
        lag = r[f"{side}_lag"]
        if lag.isdigit():
            max_lag[side] = max(max_lag[side], int(lag))
            if int(lag) > 2 and (prev is None or not prev[f"{side}_lag"].isdigit() or int(prev[f"{side}_lag"]) <= 2):
                events.append((t, f"{label} 복제 지연 {lag}초"))
        bad = bool(writer and host != writer and r[f"{side}_app"].isdigit() and int(r[f"{side}_app"]) > 0)
        if bad and not streak[side]:
            streak[side] = t
            events.append((t, f"!! 쓰기 대상이 아닌 {label}에 앱 연결 {r[f'{side}_app']}개 시작 (split-brain 의심)"))
        elif not bad and streak[side]:
            events.append((t, f"   {label} 앱 연결 0으로 돌아옴 ({streak[side]}부터)"))
            streak[side] = None
        d = 0
        if writer and host != writer and prev and prev["proxy_online"] == writer:
            # 이번 샘플에서 쓰기 대상을 복제 중이면, 그동안의 증가는 복제 적용분(밀린 분 따라잡기 포함)으로 본다
            replicating = r[f"{side}_src"] == writer and r[f"{side}_io"] == "Yes" and r[f"{side}_sql"] == "Yes"
            if not replicating:
                try:
                    d = sum(int(r[f"{side}_{c}"]) - int(prev[f"{side}_{c}"]) for c in ("com_ins", "com_upd", "com_del"))
                except ValueError:
                    d = 0
        if d > 0:
            if com[side]:
                com[side][1] = t
                com[side][2] += d
            else:
                com[side] = [t, t, d]
        else:
            flush_com(side)
    prev = r
for side in ("old", "new"):
    flush_com(side)
    if streak[side]:
        events.append((rows[-1]["ts_utc"], f"!! {name[old if side == 'old' else new]} 앱 연결이 끝까지 남아 있음 ({streak[side]}부터)"))
events.sort(key=lambda e: e[0])
print(f"측정: {rows[0]['ts_utc']} ~ {rows[-1]['ts_utc']} UTC, {len(rows)}개 샘플" + (f" (열 개수가 맞지 않는 줄 {skipped}개 건너뜀)" if skipped else ""))
print(f"구 DB = {old}\n신 DB = {new}\n")
for t, e in events:
    print(f"{t}  {e}")
print(f"\n최대 복제 지연: 구 DB {max_lag['old']}초, 신 DB {max_lag['new']}초")
def growth(k):
    try:
        a, b = int(rows[0][k] or 0), int(rows[-1][k] or 0)
        return f"+{b - a} (측정 시작 시 누적 {a})"
    except ValueError:
        return "알 수 없음"
print(f"마지막 상태: 쓰기 대상={name.get(rows[-1]['proxy_online'], rows[-1]['proxy_online'])}")
print(f"측정 구간 증가: ProxySQL 에러 {growth('proxy_err_total')}, 연결 획득 실패 {growth('connpool_get_fail')}")
PY
}

if [[ "${1:-}" == "report" ]]; then
  report "${2:-}"
  exit 0
fi

# shellcheck source=lib-mysql-cli.sh
source "${SCRIPT_DIR}/lib-mysql-cli.sh"

ENV_NAME="${1:-}"
OLD_HOST="${2:-}"
NEW_HOST="${3:-}"
INTERVAL="${4:-1}"
[[ "$ENV_NAME" =~ ^(dev|prod)$ && -n "$OLD_HOST" && -n "$NEW_HOST" && "$INTERVAL" =~ ^[0-9.]+$ ]] || {
  echo "usage: observe.sh <dev|prod> <old-db> <new-db> [interval-sec]  |  observe.sh report <csv>"
  exit 64
}

LOG_DIR="${SCRIPT_DIR}/logs"
mkdir -p "$LOG_DIR"
CSV="${LOG_DIR}/observe-$(date -u '+%Y%m%d-%H%M%S').csv"

# Ctrl+C는 플래그만 세우고, 루프 경계에서 멈춘다 (기록 중이던 샘플은 버림)
STOP=0
trap 'STOP=1' INT TERM
trap 'stop_cli' EXIT

load_credentials "$ENV_NAME"
start_cli

APP_FILTER="user NOT IN ('${RDS_ADMIN}', 'repl', 'rdsadmin', 'event_scheduler', 'system user', 'unauthenticated user')"

# 한 DB의 상태를 key=value 한 줄로 (세로 출력 -E를 파싱)
db_state() {
  printf '%s\n' "SELECT @@GLOBAL.read_only AS ro, (SELECT COUNT(*) FROM information_schema.processlist WHERE ${APP_FILTER}) AS app;
SHOW GLOBAL STATUS WHERE Variable_name IN ('Com_insert','Com_update','Com_delete');
SHOW BINARY LOG STATUS;
SHOW REPLICA STATUS;" \
    | MYSQL_PWD="$RDS_ADMIN_PW" docker exec -i -e MYSQL_PWD "$CLI_CONTAINER" \
      mysql -h "$1" -u "$RDS_ADMIN" --ssl-mode=REQUIRED --connect-timeout=3 -E 2>/dev/null \
    | awk -F': ' '
        { k=$1; gsub(/^ +/, "", k); v=substr($0, index($0, ": ")+2) }
        k=="ro" {o["ro"]=v} k=="app" {o["app"]=v}
        k=="Variable_name" {var=v} k=="Value" && var=="Com_insert" {o["ins"]=v} k=="Value" && var=="Com_update" {o["upd"]=v} k=="Value" && var=="Com_delete" {o["del"]=v}
        k=="File" {o["binlog"]=v} k=="Position" {o["binlog"]=o["binlog"] ":" v}
        k=="Source_Host" {o["src"]=v} k=="Replica_IO_Running" {o["io"]=v} k=="Replica_SQL_Running" {o["sql"]=v}
        k=="Seconds_Behind_Source" {o["lag"]=v} k=="Relay_Source_Log_File" {rf=v} k=="Exec_Source_Log_Pos" {o["exec"]=rf ":" v}
        k=="Last_IO_Error" && v!="" {o["err"]=o["err"] "IO:" v " "} k=="Last_SQL_Error" && v!="" {o["err"]=o["err"] "SQL:" v}
        END { gsub(/[,\n]/, " ", o["err"]); printf "%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s", o["ro"], o["app"], o["ins"], o["upd"], o["del"], o["binlog"], o["src"], o["io"], o["sql"], o["lag"], o["exec"], o["err"] }'
}

proxy_state() {
  local online pool err glob
  online="$(q_admin "SELECT hostname FROM runtime_mysql_servers WHERE hostgroup_id=${WRITER_HOSTGROUP} AND status='ONLINE'" 2>/dev/null | paste -sd'|' -)"
  pool="$(q_admin "SELECT srv_host || ':' || status || ':' || ConnUsed || ':' || ConnFree || ':' || Queries FROM stats_mysql_connection_pool WHERE hostgroup=${WRITER_HOSTGROUP}" 2>/dev/null | paste -sd';' -)"
  err="$(q_admin "SELECT COALESCE(SUM(count_star),0) FROM stats_mysql_errors" 2>/dev/null)"
  glob="$(q_admin "SELECT variable_name, variable_value FROM stats_mysql_global WHERE variable_name IN ('Client_Connections_connected','Questions','ConnPool_get_conn_failure')" 2>/dev/null \
    | awk -F'\t' '{v[$1]=$2} END {printf "%s,%s,%s", v["Client_Connections_connected"], v["Questions"], v["ConnPool_get_conn_failure"]}')"
  printf '%s,%s,%s,%s' "$online" "$pool" "${err:-}" "$glob"
}

HEADER="ts_utc,epoch,old_host,new_host,proxy_online,proxy_pool,proxy_err_total,client_conns,questions,connpool_get_fail"
for side in old new; do
  for c in ro app com_ins com_upd com_del binlog src io sql lag exec err; do HEADER+=",${side}_${c}"; done
done
echo "$HEADER" > "$CSV"
log "수집 시작 (${INTERVAL}초 간격, Ctrl+C로 종료): ${CSV}"

NCOMMA="$(tr -cd ',' <<<"$HEADER" | wc -c)"
n=0
bad=0
while ((STOP == 0)); do
  t0="$(date +%s.%N)"
  line="$(date -u '+%H:%M:%S'),$(date +%s),${OLD_HOST},${NEW_HOST},$(proxy_state),$(db_state "$OLD_HOST"),$(db_state "$NEW_HOST")"
  ((STOP == 0)) || break
  if [[ "$(tr -cd ',' <<<"$line" | wc -c)" -eq "$NCOMMA" ]]; then
    echo "$line" >> "$CSV"
    n=$((n + 1))
    if ((n % 30 == 0)); then
      log "샘플 ${n}개"
    fi
  else
    bad=$((bad + 1))
    log "열 개수가 맞지 않는 샘플 버림 (누적 ${bad}개)"
  fi
  sleep "$(awk -v a="$t0" -v b="$(date +%s.%N)" -v i="$INTERVAL" 'BEGIN {d=i-(b-a); print (d>0)?d:0}')" || true
done
echo
log "수집 종료: ${CSV} (샘플 ${n}개)"
log "요약: ${SCRIPT_DIR}/observe.sh report ${CSV}"
