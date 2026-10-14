#!/usr/bin/env bash
# EC2 배치 경로: /opt/lookddak/v1-mysql-migration/cutover.sh
# 사용법:
#   점검만:  sudo /opt/lookddak/v1-mysql-migration/cutover.sh <dev|prod> <전환 대상 DB 엔드포인트> --check
#   전환:    sudo /opt/lookddak/v1-mysql-migration/cutover.sh <dev|prod> <전환 대상 DB 엔드포인트>
#
# 역할: ProxySQL 쓰기 대상을 현재 DB(SOURCE)에서 전환 대상 DB(TARGET)로 바꾼다.
#   - SOURCE: ProxySQL hostgroup 10에서 현재 ONLINE인 DB (자동 판별)
#   - TARGET: SOURCE를 위치 기반으로 복제 중인 DB (인자로 지정)
#   - 신 DB로 전환할 때도, 구 DB로 롤백할 때도 같은 스크립트를 쓴다. (TARGET만 바꿔 지정)
#
# 전환 순서 (사용자 쓰기 대기는 [1]~[5] 구간)
#   [1] ProxySQL: SOURCE → OFFLINE_SOFT (새 쿼리 대기 시작)
#   [2] SOURCE 펜싱
#       a. ProxySQL ConnUsed=0 + SOURCE 실행 중 쿼리·트랜잭션 0 대기 (사용 중인 연결은 끊지 않음)
#       b. ProxySQL: SOURCE → OFFLINE_HARD (놀고 있는 백엔드 연결만 남아 있으므로 앱 에러 없음)
#       c. SOURCE에 앱 연결이 0개인지 확인 → 이후 SOURCE에 쓰기가 들어올 경로 없음
#     ※ ProxySQL은 멀티플렉싱이 꺼진 세션(@@ 변수 조회 등)을 백엔드 연결에 고정한다.
#       고정된 세션은 OFFLINE_SOFT 이후에도 계속 SOURCE로 쿼리를 보내므로 ConnUsed가 0이 되지 않는다.
#       이 경우 [2a]에서 원복한다. (proxysql.cnf의 multiplex=2 쿼리 룰로 고정을 막는 것이 전제)
#   [3] SOURCE 최종 binlog 위치(②) 기록 → TARGET SOURCE_POS_WAIT
#   [4] TARGET binlog 위치(③) 기록 → TARGET 복제 중지·해제
#   [5] ProxySQL: TARGET ONLINE, SOURCE OFFLINE_HARD (대기 쿼리가 TARGET에서 실행)
#   [6] 역방향 복제: SOURCE가 ③ 위치부터 TARGET을 복제 (롤백 경로)
#
# 실패 시 자동 원복
#   [1]~[3] 실패: SOURCE를 다시 ONLINE → 대기 쿼리가 SOURCE에서 실행 (데이터 영향 없음)
#   [4]~[5] 실패: TARGET 복제를 ② 위치로 다시 연결 + SOURCE ONLINE
#
# 사전 조건 (--check로 확인)
#   - TARGET 복제 Yes/Yes, 원본 = SOURCE, 지연 0
#   - TARGET read_only = 0 (파라미터 그룹을 미리 바꿔 반영까지 확인)
#   - SOURCE에 60초 넘는 트랜잭션 없음
#   - ProxySQL mysql-connect_timeout_server_max >= 15000
#
# 종료 코드: 0 성공 / 1 실패 후 원복 성공 / 2 원복 실패(즉시 수동 확인) / 3 점검 실패 / 64 입력 오류

# shellcheck disable=SC2016  # check()의 조건식은 일부러 작은따옴표로 넘긴다
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib-mysql-cli.sh
source "${SCRIPT_DIR}/lib-mysql-cli.sh"

ENV_NAME="${1:-}"
TARGET="${2:-}"
MODE="${3:-run}"

[[ "$ENV_NAME" =~ ^(dev|prod)$ && -n "$TARGET" && "$MODE" =~ ^(run|--check)$ ]] || {
  echo "usage: cutover.sh <dev|prod> <target-db-endpoint> [--check]"
  exit 64
}

readonly DRAIN_TIMEOUT=10       # [2a] 실행 중 쿼리·트랜잭션 대기 (초)
readonly FENCE_TIMEOUT=5        # [2c] OFFLINE_HARD 후 SOURCE 앱 연결 0 대기 (초)
readonly CATCHUP_TIMEOUT=10     # [3] SOURCE_POS_WAIT (초)
readonly MIN_PROXY_WAIT_MS=15000

LOG_DIR="${SCRIPT_DIR}/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/cutover-$(date '+%Y%m%d-%H%M%S')-${MODE#--}.log"
exec > >(tee -a "$LOG_FILE") 2>&1

STAGE=0
SOURCE=""
POS2_FILE="" POS2_POS="" POS3_FILE="" POS3_POS=""
T_START=""

now() { date +%s.%N; }
elapsed() { awk -v a="$1" -v b="$(now)" 'BEGIN {printf "%.3f", b - a}'; }

proxy_set_status() {
  q_admin "UPDATE mysql_servers SET status='$2' WHERE hostgroup_id=${WRITER_HOSTGROUP} AND hostname='$1'; LOAD MYSQL SERVERS TO RUNTIME;"
}

rollback() {
  local rc=0
  trap - ERR
  set +e
  log "!!! 실패 (stage=${STAGE}) → 원복 시작"

  if ((STAGE >= 4)); then
    log "원복: TARGET을 ProxySQL에서 제거하고, TARGET 복제를 ② ${POS2_FILE}:${POS2_POS}로 다시 연결"
    q_admin "DELETE FROM mysql_servers WHERE hostgroup_id=${WRITER_HOSTGROUP} AND hostname='${TARGET}'; LOAD MYSQL SERVERS TO RUNTIME;" || rc=2
    q_db "$TARGET" "CALL mysql.rds_stop_replication;" >/dev/null 2>&1
    q_db "$TARGET" "CALL mysql.rds_reset_external_source;" >/dev/null 2>&1
    q_db "$TARGET" "CALL mysql.rds_set_external_source('${SOURCE}', 3306, 'repl', '${REPL_PW}', '${POS2_FILE}', ${POS2_POS}, 1); CALL mysql.rds_start_replication;" >/dev/null || rc=2
  fi

  if ((STAGE >= 1)); then
    log "원복: ProxySQL SOURCE → ONLINE"
    proxy_set_status "$SOURCE" ONLINE || rc=2
    q_admin_v "SELECT hostgroup_id, hostname, status FROM runtime_mysql_servers WHERE hostgroup_id=${WRITER_HOSTGROUP}"
  fi

  if ((rc == 0)); then
    log "원복 완료 (쓰기 대상: SOURCE). 경과 $( [[ -n "$T_START" ]] && elapsed "$T_START" )초"
    exit 1
  fi
  log "원복 중 오류. ProxySQL runtime_mysql_servers와 TARGET 복제 상태를 즉시 확인하세요."
  exit 2
}

trap 'stop_cli' EXIT

load_credentials "$ENV_NAME"
REPL_PW="$(get_parameter "/lookddak/${ENV_NAME}/rds/repl/password")"
start_cli

# ---------------------------------------------------------------
# 사전 점검
# ---------------------------------------------------------------
log "=== 사전 점검 (env=${ENV_NAME}, log=${LOG_FILE})"
CHECK_FAIL=0
# check "<설명>" '<조건식>' : 조건식은 작은따옴표로 넘겨 eval 시점에 평가한다.
check() {
  if eval "$2"; then log "  [OK]   $1"; else log "  [FAIL] $1"; CHECK_FAIL=1; fi
}

SOURCE="$(q_admin "SELECT hostname FROM runtime_mysql_servers WHERE hostgroup_id=${WRITER_HOSTGROUP} AND status='ONLINE'")"
log "SOURCE (현재 쓰기 대상): ${SOURCE:-없음}"
log "TARGET (전환 대상):      ${TARGET}"
check "ProxySQL ONLINE 쓰기 대상이 정확히 하나" '[[ -n "$SOURCE" && "$(wc -l <<<"$SOURCE")" -eq 1 ]]'
check "TARGET이 현재 쓰기 대상이 아님" '[[ "$SOURCE" != "$TARGET" ]]'
((CHECK_FAIL == 0)) || { log "점검 실패"; exit 3; }

R_IO="$(replica_field "$TARGET" Replica_IO_Running)"
R_SQL="$(replica_field "$TARGET" Replica_SQL_Running)"
R_LAG="$(replica_field "$TARGET" Seconds_Behind_Source)"
R_SRC="$(replica_field "$TARGET" Source_Host)"
T_RO="$(q_db "$TARGET" "SELECT @@GLOBAL.read_only")"
LONG_TRX="$(q_db "$SOURCE" "SELECT COUNT(*) FROM information_schema.innodb_trx WHERE trx_started < NOW() - INTERVAL 60 SECOND")"
PROXY_WAIT="$(q_admin "SELECT variable_value FROM runtime_global_variables WHERE variable_name='mysql-connect_timeout_server_max'")"
SRC_ROW="$(q_admin "SELECT use_ssl, max_connections FROM runtime_mysql_servers WHERE hostgroup_id=${WRITER_HOSTGROUP} AND hostname='${SOURCE}'")"
SRC_USE_SSL="$(cut -f1 <<<"$SRC_ROW")"
SRC_MAX_CONN="$(cut -f2 <<<"$SRC_ROW")"

log "TARGET 복제: IO=${R_IO} SQL=${R_SQL} lag=${R_LAG} source=${R_SRC}"
log "TARGET read_only=${T_RO}, SOURCE 60초 초과 트랜잭션=${LONG_TRX}, ProxySQL 대기 한도=${PROXY_WAIT}ms"
check "TARGET 복제 실행 중 (Yes/Yes)" '[[ "$R_IO" == "Yes" && "$R_SQL" == "Yes" ]]'
check "TARGET 복제 원본 = SOURCE" '[[ "$R_SRC" == "$SOURCE" ]]'
check "TARGET 복제 지연 0" '[[ "$R_LAG" == "0" ]]'
check "TARGET read_only = 0 (미리 해제)" '[[ "$T_RO" == "0" ]]'
check "SOURCE 긴 트랜잭션 없음" '[[ "$LONG_TRX" == "0" ]]'
check "ProxySQL 대기 한도 >= ${MIN_PROXY_WAIT_MS}ms" '[[ "${PROXY_WAIT:-0}" -ge "$MIN_PROXY_WAIT_MS" ]]'
check "repl 비밀번호 확인 (원복·역방향 복제용)" '[[ -n "$REPL_PW" ]]'

if ((CHECK_FAIL != 0)); then
  log "점검 실패. 전환하지 않습니다."
  exit 3
fi
if [[ "$MODE" == "--check" ]]; then
  log "점검 통과 (--check 모드라 전환하지 않음)"
  exit 0
fi

trap rollback ERR

# ---------------------------------------------------------------
# 전환
# ---------------------------------------------------------------
log "=== 전환 시작"
T_START="$(now)"

# [1]
STAGE=1
proxy_set_status "$SOURCE" OFFLINE_SOFT
log "[1] ProxySQL SOURCE → OFFLINE_SOFT (새 쿼리 대기 시작)"

# [2] SOURCE 펜싱
STAGE=2
# 앱 연결 = 관리자(이 스크립트)·복제·RDS 내부 계정을 제외한 연결
APP_FILTER="user NOT IN ('${RDS_ADMIN}', 'repl', 'rdsadmin', 'event_scheduler', 'system user')"
src_count() {
  q_db "$SOURCE" "SELECT
    (SELECT COUNT(*) FROM information_schema.innodb_trx WHERE trx_mysql_thread_id <> CONNECTION_ID()),
    (SELECT COUNT(*) FROM information_schema.processlist WHERE ${APP_FILTER} AND command <> 'Sleep'),
    (SELECT COUNT(*) FROM information_schema.processlist WHERE ${APP_FILTER})"
}

# [2a] ProxySQL이 SOURCE 연결을 모두 반납(ConnUsed=0)하고, SOURCE에 실행 중 쿼리·트랜잭션이 없을 때까지 대기
#      ConnUsed=0이면 어떤 클라이언트 세션도 SOURCE 연결을 쥐고 있지 않으므로,
#      [2b]의 OFFLINE_HARD는 놀고 있는 연결(ConnFree)만 닫는다 → 앱 에러 없음.
#      세션이 연결에 고정(멀티플렉싱 해제)돼 있으면 0이 되지 않으므로 끊지 않고 원복한다.
deadline=$(( $(date +%s) + DRAIN_TIMEOUT ))
while :; do
  used="$(q_admin "SELECT COALESCE(SUM(ConnUsed),0) FROM stats_mysql_connection_pool WHERE hostgroup=${WRITER_HOSTGROUP} AND srv_host='${SOURCE}'")"
  read -r trx active conns <<<"$(src_count)"
  [[ "$used" == "0" && "$trx" == "0" && "$active" == "0" ]] && break
  if (( $(date +%s) >= deadline )); then
    log "[2a] ${DRAIN_TIMEOUT}초 안에 연결이 반납되지 않음 (ConnUsed=${used}, innodb_trx=${trx}, active=${active}, app_conns=${conns})"
    log "[2a] ConnUsed가 계속 남으면 세션이 연결에 고정된 상태입니다 (stats_mysql_processlist에서 Sleep + srv_host 확인)"
    false
  fi
  sleep 0.2
done
log "[2a] ProxySQL ConnUsed=0, SOURCE 실행 중 쿼리·트랜잭션 없음 (+$(elapsed "$T_START")s)"

# [2b] 놀고 있는 백엔드 연결 닫기
proxy_set_status "$SOURCE" OFFLINE_HARD
log "[2b] ProxySQL SOURCE → OFFLINE_HARD (TARGET은 아직 OFFLINE이라 새 쿼리는 계속 대기)"

# [2c] SOURCE 앱 연결 0 확인 = 펜스 완료
deadline=$(( $(date +%s) + FENCE_TIMEOUT ))
while :; do
  read -r trx active conns <<<"$(src_count)"
  [[ "$trx" == "0" && "$conns" == "0" ]] && break
  if (( $(date +%s) >= deadline )); then
    log "[2c] ${FENCE_TIMEOUT}초 안에 SOURCE 앱 연결이 닫히지 않음 (app_conns=${conns}, innodb_trx=${trx})"
    q_db_v "$SOURCE" "SELECT id, user, host, command, time, state FROM information_schema.processlist WHERE ${APP_FILTER}" || true
    false
  fi
  sleep 0.2
done
log "[2c] SOURCE 앱 연결 0, 트랜잭션 0 → 펜스 완료 (+$(elapsed "$T_START")s)"

# [3]
STAGE=3
pos="$(binlog_position "$SOURCE")"
POS2_FILE="${pos%%$'\t'*}"
POS2_POS="${pos##*$'\t'}"
log "[3] ② SOURCE 최종 위치 ${POS2_FILE}:${POS2_POS}"
wait_result="$(q_db "$TARGET" "SELECT SOURCE_POS_WAIT('${POS2_FILE}', ${POS2_POS}, ${CATCHUP_TIMEOUT})")"
log "[3] TARGET SOURCE_POS_WAIT=${wait_result} (+$(elapsed "$T_START")s)"
[[ "$wait_result" != "NULL" && "$wait_result" -ge 0 ]]

# [4]
STAGE=4
pos="$(binlog_position "$TARGET")"
POS3_FILE="${pos%%$'\t'*}"
POS3_POS="${pos##*$'\t'}"
log "[4] ③ TARGET 시작 위치 ${POS3_FILE}:${POS3_POS}"
q_db "$TARGET" "CALL mysql.rds_stop_replication; CALL mysql.rds_reset_external_source;" >/dev/null
log "[4] TARGET 복제 중지·해제 (+$(elapsed "$T_START")s)"

# [5]
STAGE=5
# LOAD TO RUNTIME이 실제 전환 시점. 이 명령 이후로는 TARGET이 쓰기를 받으므로 원복하지 않는다.
q_admin "REPLACE INTO mysql_servers (hostgroup_id, hostname, port, use_ssl, max_connections, status) VALUES (${WRITER_HOSTGROUP}, '${TARGET}', 3306, ${SRC_USE_SSL:-1}, ${SRC_MAX_CONN:-100}, 'ONLINE'); UPDATE mysql_servers SET status='OFFLINE_HARD' WHERE hostgroup_id=${WRITER_HOSTGROUP} AND hostname='${SOURCE}'; LOAD MYSQL SERVERS TO RUNTIME;"
WAIT_SECONDS="$(elapsed "$T_START")"
trap - ERR
STAGE=6
log "[5] ProxySQL TARGET → ONLINE, SOURCE → OFFLINE_HARD"
log "=== 전환 완료: 쓰기 대기 구간 ${WAIT_SECONDS}초"
q_admin "SAVE MYSQL SERVERS TO DISK;" || log "경고: SAVE MYSQL SERVERS TO DISK 실패 (runtime은 전환됨)"

# [6] 역방향 복제 (실패해도 전환은 유지, 경고만)
set +e
q_db "$SOURCE" "CALL mysql.rds_stop_replication;" >/dev/null 2>&1
q_db "$SOURCE" "CALL mysql.rds_reset_external_source;" >/dev/null 2>&1
q_db "$SOURCE" "CALL mysql.rds_set_external_source('${TARGET}', 3306, 'repl', '${REPL_PW}', '${POS3_FILE}', ${POS3_POS}, 1); CALL mysql.rds_start_replication;" >/dev/null
sleep 3
B_IO="$(replica_field "$SOURCE" Replica_IO_Running)"
B_SQL="$(replica_field "$SOURCE" Replica_SQL_Running)"
B_ERR="$(replica_field "$SOURCE" Last_IO_Error)$(replica_field "$SOURCE" Last_SQL_Error)"
if [[ "$B_IO" == "Yes" && "$B_SQL" == "Yes" ]]; then
  log "[6] 역방향 복제 시작: SOURCE가 TARGET ${POS3_FILE}:${POS3_POS}부터 복제 (롤백 경로 확보)"
else
  log "[6] 경고: 역방향 복제 확인 필요 (IO=${B_IO} SQL=${B_SQL} ${B_ERR})"
fi
set -e

# ---------------------------------------------------------------
# 결과·증적
# ---------------------------------------------------------------
log "=== 결과"
q_admin_v "SELECT hostgroup_id, hostname, status FROM runtime_mysql_servers WHERE hostgroup_id=${WRITER_HOSTGROUP}"
q_admin_v "SELECT hostgroup, srv_host, status, ConnUsed, ConnFree, Queries FROM stats_mysql_connection_pool WHERE hostgroup=${WRITER_HOSTGROUP}"
q_admin_v "SELECT errno, count_star, last_error FROM stats_mysql_errors"

cat <<EOF

=== 증적
SOURCE (이전 쓰기 대상)   ${SOURCE}
TARGET (새 쓰기 대상)     ${TARGET}
② SOURCE 최종 위치        ${POS2_FILE}:${POS2_POS}
SOURCE_POS_WAIT 결과      ${wait_result}
③ TARGET 시작 위치        ${POS3_FILE}:${POS3_POS}
쓰기 대기 구간            ${WAIT_SECONDS}초
로그                      ${LOG_FILE}

=== 남은 작업 (수동)
1. SOURCE 쓰기 차단: SOURCE 파라미터 그룹 read_only = 1 (Terraform 코드에도 반영)
2. proxysql.cnf의 mysql_servers hostname을 TARGET으로 변경 (컨테이너 재생성 시 유지되도록)
   단일 파일 bind mount라 sed -i(파일 교체)를 쓰면 컨테이너가 옛 파일을 계속 본다 → cat >로 덮어쓴다.
     cd ${SCRIPT_DIR}
     cp -p proxysql.cnf proxysql.cnf.bak-\$(date +%Y%m%d%H%M%S)
     sed 's#hostname="${SOURCE}"#hostname="${TARGET}"#' proxysql.cnf > proxysql.cnf.new
     diff proxysql.cnf proxysql.cnf.new
     cat proxysql.cnf.new > proxysql.cnf && rm proxysql.cnf.new
3. TARGET read_only = 0을 Terraform 코드에도 반영 (mysql_read_only = false)
4. 롤백이 필요하면: cutover.sh ${ENV_NAME} ${SOURCE}
   (SOURCE read_only = 0을 먼저 반영한 뒤 실행)
EOF
