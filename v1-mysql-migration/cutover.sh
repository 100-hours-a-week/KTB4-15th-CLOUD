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
# 사전 점검 (쿼리를 막기 전, 사용자 영향 없음) → 실패하면 아무것도 바꾸지 않음
#
# 전환 순서 (사용자 쓰기 대기는 [1]~[5] 구간)
#   [1] ProxySQL: SOURCE → OFFLINE_SOFT (새 쿼리를 ProxySQL에서 대기시킴)              ProxySQL
#   [2] SOURCE 펜싱 (SOURCE가 더 이상 앱 쓰기를 받지 못하게 격리하고 확인)
#       a. ProxySQL ConnUsed=0 + SOURCE 실행 중 쿼리·트랜잭션 0 대기 (사용 중인 연결은 끊지 않음)  ProxySQL, SOURCE
#       b. ProxySQL: SOURCE → OFFLINE_HARD (놀고 있는 백엔드 연결만 남아 있으므로 앱 에러 없음)  ProxySQL
#       c. SOURCE에 앱 연결이 0개인지 확인 → 이후 SOURCE에 쓰기가 들어올 경로 없음           SOURCE
#     ※ ProxySQL은 멀티플렉싱이 꺼진 세션(@@ 변수 조회 등)을 백엔드 연결에 고정한다.
#       고정된 세션은 OFFLINE_SOFT 이후에도 계속 SOURCE로 쿼리를 보내므로 ConnUsed가 0이 되지 않는다.
#       이 경우 [2a]에서 원복한다. (proxysql.cnf의 multiplex=2 쿼리 룰로 고정을 막는 것이 전제)
#   [3] ② 기록: SOURCE binlog의 마지막 위치 (SOURCE에서 SHOW BINARY LOG STATUS)            SOURCE
#       TARGET이 ②까지 실행했는지 확인 (TARGET에서 SOURCE_POS_WAIT) → 두 DB 데이터 일치     TARGET
#   [4] ③ 기록: TARGET binlog의 현재 끝 (TARGET에서 SHOW BINARY LOG STATUS)                TARGET
#       ③ 앞 = 복제로 받은 SOURCE 변경(SOURCE에 이미 있음), ③ 뒤 = [5] 이후 앱 쓰기 → 롤백용 역방향 복제의 시작점
#   [5] ProxySQL: TARGET ONLINE, SOURCE 행 삭제 (대기 쿼리가 TARGET에서 실행)             ProxySQL
#       삭제 후 LOAD하면 ProxySQL은 SOURCE를 OFFLINE_HARD와 같이 처리한다.
#       OFFLINE_HARD 행을 남기면 memory·disk에만 SOURCE가 남아 cnf(1행)와 어긋나므로 지운다.
#   [6] TARGET 복제 중지·해제 (rds_stop_replication 약 3초 → 사용자 대기 밖으로 뺌)          TARGET
#       SOURCE는 [2]에서 펜싱되어 복제로 들어올 앱 변경이 없으므로, ONLINE 뒤에 끊어도 데이터 영향 없음
#   [7] 역방향 복제: SOURCE가 ③ 위치부터 TARGET을 복제 (롤백 경로)                         SOURCE
#       [6]이 성공해야만 실행 (TARGET이 SOURCE를 계속 복제 중이면 양방향 순환이 되므로)
#
# 실패 처리
#   [1]~[4] 실패: SOURCE를 다시 ONLINE → 대기 쿼리가 SOURCE에서 실행 (데이터 영향 없음, TARGET 복제는 그대로)
#   [5] 이후: 원복하지 않음 (TARGET이 쓰기를 받기 시작했으므로, 되돌리려면 롤백 = 반대 방향 전환)
#   [6] 실패: [7]을 건너뛰고 수동 조치 안내 (종료 코드 2). 쓰기 경로는 TARGET 하나라 데이터 문제 없음
#   [7] 실패: 경고와 수동 조치 안내 (종료 코드 2)
#
# 사전 점검 항목과 이유
#   - ProxySQL ONLINE 1개: 쓰기 경로가 하나인 상태에서 시작
#   - TARGET 복제 Yes/Yes, 원본 = SOURCE: 끊긴 복제는 수 초 안에 고칠 수 없으므로 쿼리를 막기 전에 거른다
#   - TARGET 지연 <= MAX_LAG초: [3] 따라잡기(CATCHUP_TIMEOUT) 안에 끝날지 보는 준비 확인.
#     Seconds_Behind_Source는 초 단위 근사치라 정합성 근거로 쓰지 않는다 (정합성은 [3]의 위치 비교)
#   - TARGET read_only = 0: RDS는 SET GLOBAL read_only가 안 되고 파라미터 그룹으로만 바꿀 수 있으며 반영이 비동기다.
#     전환 중 늦게 반영되면 [5] 이후 대기하던 쓰기가 read-only 에러를 받으므로 미리 반영해 둔다.
#   - SOURCE에 60초 넘게 열린 트랜잭션 없음: [2a]의 DRAIN_TIMEOUT 안에 끝나지 않을 가능성이 높아,
#     사용자를 기다리게만 하고 원복될 전환을 시작하지 않는다 (안전장치가 아니라 헛된 대기 방지)
#   - ProxySQL 대기 한도(mysql-connect_timeout_server_max) >= 단계별 대기 한도 합:
#     ONLINE 서버가 없는 동안 쿼리는 이 한도까지 대기하고, 넘으면 DB에 보내지 않고 ERROR 9001.
#     최악의 경우 [2a]+[2c]+[3] 한도 + 여유만큼 대기할 수 있으므로 그보다 길어야 한다.
#
# 종료 코드: 0 성공 / 1 실패 후 원복 성공 / 2 수동 확인 필요 / 3 점검 실패 / 64 입력 오류

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
readonly STEP_MARGIN=5          # 조회·ProxySQL LOAD 등 나머지 단계 여유 (초)
readonly MAX_LAG=2              # 사전 점검: TARGET 복제 지연 허용 (초)
readonly LONG_TRX_SECONDS=60    # 사전 점검: 이보다 오래 열린 SOURCE 트랜잭션이 있으면 시작하지 않음
# 사용자 대기 최악값 = [2a] + [2c] + [3] + 여유 → ProxySQL 대기 한도는 이보다 길어야 한다
readonly MIN_PROXY_WAIT_MS=$(( (DRAIN_TIMEOUT + FENCE_TIMEOUT + CATCHUP_TIMEOUT + STEP_MARGIN) * 1000 ))

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

# shellcheck disable=SC2329  # trap ERR로 호출된다
rollback() {
  local rc=0
  trap - ERR
  set +e
  log "!!! 실패 (stage=${STAGE}) → 원복 시작"

  if ((STAGE >= 1)); then
    log "원복: ProxySQL SOURCE → ONLINE"
    proxy_set_status "$SOURCE" ONLINE || rc=2
    q_admin_v "SELECT hostgroup_id, hostname, status FROM runtime_mysql_servers WHERE hostgroup_id=${WRITER_HOSTGROUP}"
  fi

  if ((rc == 0)); then
    log "원복 완료 (쓰기 대상: SOURCE). 경과 $( [[ -n "$T_START" ]] && elapsed "$T_START" )초"
    exit 1
  fi
  log "원복 중 오류. ProxySQL runtime_mysql_servers를 즉시 확인하세요."
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
LONG_TRX="$(q_db "$SOURCE" "SELECT COUNT(*) FROM information_schema.innodb_trx WHERE trx_started < NOW() - INTERVAL ${LONG_TRX_SECONDS} SECOND")"
PROXY_WAIT="$(q_admin "SELECT variable_value FROM runtime_global_variables WHERE variable_name='mysql-connect_timeout_server_max'")"
SRC_ROW="$(q_admin "SELECT use_ssl, max_connections FROM runtime_mysql_servers WHERE hostgroup_id=${WRITER_HOSTGROUP} AND hostname='${SOURCE}'")"
SRC_USE_SSL="$(cut -f1 <<<"$SRC_ROW")"
SRC_MAX_CONN="$(cut -f2 <<<"$SRC_ROW")"

log "TARGET 복제: IO=${R_IO} SQL=${R_SQL} lag=${R_LAG} source=${R_SRC}"
log "TARGET read_only=${T_RO}, SOURCE ${LONG_TRX_SECONDS}초 초과 트랜잭션=${LONG_TRX}, ProxySQL 대기 한도=${PROXY_WAIT}ms"
check "TARGET 복제 실행 중 (Yes/Yes)" '[[ "$R_IO" == "Yes" && "$R_SQL" == "Yes" ]]'
check "TARGET 복제 원본 = SOURCE" '[[ "$R_SRC" == "$SOURCE" ]]'
check "TARGET 복제 지연 <= ${MAX_LAG}초" '[[ "$R_LAG" =~ ^[0-9]+$ && "$R_LAG" -le "$MAX_LAG" ]]'
check "TARGET read_only = 0 (미리 해제)" '[[ "$T_RO" == "0" ]]'
check "SOURCE ${LONG_TRX_SECONDS}초 초과 트랜잭션 없음" '[[ "$LONG_TRX" == "0" ]]'
check "ProxySQL 대기 한도 >= ${MIN_PROXY_WAIT_MS}ms ([2a]+[2c]+[3] 한도 + 여유)" '[[ "${PROXY_WAIT:-0}" -ge "$MIN_PROXY_WAIT_MS" ]]'
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

# [3] ② 기록 (SOURCE) → TARGET이 ②까지 실행했는지 확인 (TARGET)
#     ②는 펜스 이후에 읽으므로 SOURCE 앱 쓰기의 끝이 확정된 위치다.
#     SOURCE_POS_WAIT는 복제받는 쪽(TARGET)에서 원본(SOURCE) binlog 좌표로 기다린다.
#     (함수 이름의 SOURCE는 "복제 원본"이라는 MySQL 용어로, 이 스크립트의 SOURCE 변수와 별개)
#     반환: 0 이상 = 도달(기다린 이벤트 수), -1 = 시간 초과, NULL = 복제 스레드가 돌지 않음
STAGE=3
pos="$(binlog_position "$SOURCE")"
POS2_FILE="${pos%%$'\t'*}"
POS2_POS="${pos##*$'\t'}"
log "[3] ② SOURCE 최종 위치 ${POS2_FILE}:${POS2_POS}"
wait_result="$(q_db "$TARGET" "SELECT SOURCE_POS_WAIT('${POS2_FILE}', ${POS2_POS}, ${CATCHUP_TIMEOUT})")"
log "[3] TARGET SOURCE_POS_WAIT=${wait_result} (+$(elapsed "$T_START")s)"
[[ "$wait_result" != "NULL" && "$wait_result" -ge 0 ]]

# [4] ③ 기록 (TARGET binlog의 현재 끝)
#     [3] 이후(복제로 받은 SOURCE 변경이 모두 들어간 뒤), [5] 이전(앱 쓰기가 들어오기 전)에 읽어야
#     "SOURCE에 이미 있는 것"과 "아직 없는 것"의 경계가 된다. SOURCE가 펜싱되어 이 사이에 TARGET binlog는 늘지 않는다.
STAGE=4
pos="$(binlog_position "$TARGET")"
POS3_FILE="${pos%%$'\t'*}"
POS3_POS="${pos##*$'\t'}"
[[ -n "$POS3_FILE" && -n "$POS3_POS" ]]
log "[4] ③ TARGET 시작 위치 ${POS3_FILE}:${POS3_POS} (+$(elapsed "$T_START")s)"

# [5] 전환: LOAD TO RUNTIME이 실제 전환 시점. 이후로는 TARGET이 쓰기를 받으므로 원복하지 않는다.
STAGE=5
q_admin "REPLACE INTO mysql_servers (hostgroup_id, hostname, port, use_ssl, max_connections, status) VALUES (${WRITER_HOSTGROUP}, '${TARGET}', 3306, ${SRC_USE_SSL:-1}, ${SRC_MAX_CONN:-100}, 'ONLINE'); DELETE FROM mysql_servers WHERE hostgroup_id=${WRITER_HOSTGROUP} AND hostname='${SOURCE}'; LOAD MYSQL SERVERS TO RUNTIME;"
WAIT_SECONDS="$(elapsed "$T_START")"
trap - ERR
STAGE=6
log "[5] ProxySQL TARGET → ONLINE, SOURCE 행 삭제 (쓰기 대상은 TARGET 하나)"
log "=== 전환 완료: 쓰기 대기 구간 ${WAIT_SECONDS}초"
q_admin "SAVE MYSQL SERVERS TO DISK;" || log "경고: SAVE MYSQL SERVERS TO DISK 실패 (runtime은 전환됨)"

set +e
MANUAL=0
REVERSE_OK=0

# [6] TARGET 복제 중지·해제 (사용자 대기 밖)
#     reset까지 해야 재부팅·장애 조치 때 RDS가 복제를 자동으로 다시 시작하지 않는다.
q_db "$TARGET" "CALL mysql.rds_stop_replication;" >/dev/null
q_db "$TARGET" "CALL mysql.rds_reset_external_source;" >/dev/null
T_SRC_AFTER="$(replica_field "$TARGET" Source_Host)"
if [[ -z "$T_SRC_AFTER" ]]; then
  log "[6] TARGET 복제 중지·해제 완료 (+$(elapsed "$T_START")s)"
  # [7] 역방향 복제: SOURCE가 ③부터 TARGET을 복제
  q_db "$SOURCE" "CALL mysql.rds_stop_replication;" >/dev/null 2>&1
  q_db "$SOURCE" "CALL mysql.rds_reset_external_source;" >/dev/null 2>&1
  q_db "$SOURCE" "CALL mysql.rds_set_external_source('${TARGET}', 3306, 'repl', '${REPL_PW}', '${POS3_FILE}', ${POS3_POS}, 1); CALL mysql.rds_start_replication;" >/dev/null
  sleep 3
  B_IO="$(replica_field "$SOURCE" Replica_IO_Running)"
  B_SQL="$(replica_field "$SOURCE" Replica_SQL_Running)"
  B_ERR="$(replica_field "$SOURCE" Last_IO_Error)$(replica_field "$SOURCE" Last_SQL_Error)"
  if [[ "$B_IO" == "Yes" && "$B_SQL" == "Yes" ]]; then
    REVERSE_OK=1
    log "[7] 역방향 복제 시작: SOURCE가 TARGET ${POS3_FILE}:${POS3_POS}부터 복제 (롤백 경로 확보)"
  else
    MANUAL=1
    log "[7] 경고: 역방향 복제 확인 필요 (IO=${B_IO} SQL=${B_SQL} ${B_ERR})"
  fi
else
  MANUAL=1
  log "[6] 경고: TARGET 복제 해제 실패 (Source_Host=${T_SRC_AFTER}). 순환 복제를 막기 위해 [7] 역방향 복제를 건너뜀"
  log "[6] 쓰기 대상은 TARGET 하나이고 SOURCE는 펜싱 상태라 데이터 문제는 없음. 아래 '수동 조치'를 진행하세요."
fi
set -e

# ---------------------------------------------------------------
# 결과·증적
# ---------------------------------------------------------------
log "=== 결과"
q_admin_v "SELECT hostgroup_id, hostname, status FROM runtime_mysql_servers WHERE hostgroup_id=${WRITER_HOSTGROUP}"
q_admin_v "SELECT 'memory' AS layer, hostgroup_id, hostname, status FROM mysql_servers WHERE hostgroup_id=${WRITER_HOSTGROUP}"
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
역방향 복제               $( ((REVERSE_OK)) && echo "정상 (SOURCE ← TARGET, ③부터)" || echo "확인 필요" )
로그                      ${LOG_FILE}

=== 남은 작업 (수동)
0. (역방향 복제가 '확인 필요'일 때만) 수동 조치
   TARGET:  CALL mysql.rds_stop_replication; CALL mysql.rds_reset_external_source;  → SHOW REPLICA STATUS 결과 없음 확인
   SOURCE:  CALL mysql.rds_reset_external_source;
            CALL mysql.rds_set_external_source('${TARGET}', 3306, 'repl', '<repl 비밀번호>', '${POS3_FILE}', ${POS3_POS}, 1);
            CALL mysql.rds_start_replication;  → Yes/Yes 확인
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

exit $(( MANUAL ? 2 : 0 ))
