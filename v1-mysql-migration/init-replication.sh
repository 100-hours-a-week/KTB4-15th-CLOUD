#!/usr/bin/env bash
# EC2 배치 경로: /opt/lookddak/v1-mysql-migration/init-replication.sh
# 사용법:
#   1) 승격 전: sudo ./init-replication.sh <dev|prod> stop  <신 DB(리드 레플리카)> <구 DB>
#   2) 승격:    Terraform PR (mysql_promote = true) → apply → replicaOf 없음 확인
#   3) 승격 후: sudo ./init-replication.sh <dev|prod> start <신 DB> <구 DB> <① 위치 파일>
#
# 역할: 신 DB 초기 복제 구성 중 SQL로 하는 단계를 묶는다. (dev 초기화·prod에서 반복)
#   리드 레플리카로 구 DB를 멈추지 않고 사본을 만든 뒤, 레플리카를 멈춰 "사본과 정확히 맞는 위치(①)"를 얻고,
#   승격 후 ①부터 직접 관리하는 외부 복제로 다시 잇는다.
#
# stop  (신 DB에서 실행)
#   - 신 DB가 RDS 리드 레플리카로 복제 중인지 확인 (Source_Host 있음, Yes/Yes)
#   - 레플리카의 원본이 지정한 구 DB인지 확인: Source_Server_Id = 구 DB @@server_id
#     (RDS 리드 레플리카의 Source_Host는 원본의 RDS 내부 IP라 호스트 이름과 비교할 수 없고,
#      승격 후 외부 복제는 그 IP가 아니라 구 DB 엔드포인트로 연결해야 한다)
#   - CALL mysql.rds_stop_replication → 데이터가 멈춘 시점에 고정
#   - SHOW REPLICA STATUS에서 ① = Relay_Source_Log_File / Exec_Source_Log_Pos (구 DB binlog 좌표)
#   - 받았지만 실행 안 한 이벤트가 없어야 함: Source_Log_File = Relay_Source_Log_File, Read_Source_Log_Pos = Exec_Source_Log_Pos
#     다르면 복제를 다시 켜서 따라잡게 한 뒤 다시 멈춤 (최대 3회)
#   - ①이 구 DB binlog 목록에 있는 파일·위치인지 확인
#   - ①을 logs/position-1-<시각>.txt에 저장 (원본은 구 DB 엔드포인트로 기록)
#     승격하면 SHOW REPLICA STATUS 정보가 사라지므로 반드시 승격 전에
#   ※ 구 DB 쪽은 아무것도 하지 않는다. ① 이후 구 DB binlog는 binlog retention 안에 start로 다시 받아야 한다.
#
# start (신 DB에서 실행)
#   - 신 DB에 남은 복제 설정이 없어야 함 (승격 완료 확인, 기존 설정 덮어쓰기 방지)
#   - CALL mysql.rds_set_external_source(구 DB, 3306, 'repl', <pw>, ① 파일, ① 위치, 1) → rds_start_replication
#   - 30초 안에 Yes/Yes, 원본 = 구 DB 확인
#
# 종료 코드: 0 성공 / 1 실패 / 64 입력 오류

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib-mysql-cli.sh
source "${SCRIPT_DIR}/lib-mysql-cli.sh"

ENV_NAME="${1:-}"
MODE="${2:-}"
NEW_HOST="${3:-}"

usage() {
  echo "usage: init-replication.sh <dev|prod> stop <new-db> <old-db>"
  echo "       init-replication.sh <dev|prod> start <new-db> <old-db> <position-file>"
  exit 64
}
[[ "$ENV_NAME" =~ ^(dev|prod)$ && "$MODE" =~ ^(stop|start)$ && -n "$NEW_HOST" ]] || usage

LOG_DIR="${SCRIPT_DIR}/logs"
mkdir -p "$LOG_DIR"
exec > >(tee -a "${LOG_DIR}/init-replication-$(date '+%Y%m%d-%H%M%S')-${MODE}.log") 2>&1

trap stop_cli EXIT
load_credentials "$ENV_NAME"
start_cli

status_line() {
  log "$1 복제: source=$(replica_field "$1" Source_Host) IO=$(replica_field "$1" Replica_IO_Running) SQL=$(replica_field "$1" Replica_SQL_Running) lag=$(replica_field "$1" Seconds_Behind_Source)"
}

if [[ "$MODE" == "stop" ]]; then
  OLD_HOST="${4:-}"
  [[ -n "$OLD_HOST" ]] || usage
  [[ -n "$(replica_field "$NEW_HOST" Source_Host)" ]] || die "신 DB에 복제 정보가 없습니다 (리드 레플리카가 아니거나 이미 승격됨)"
  SRC_ID="$(replica_field "$NEW_HOST" Source_Server_Id)"
  OLD_ID="$(q_db "$OLD_HOST" "SELECT @@server_id;")"
  [[ -n "$SRC_ID" && "$SRC_ID" == "$OLD_ID" ]] || die "레플리카 원본(server_id ${SRC_ID})이 지정한 구 DB(${OLD_HOST}, server_id ${OLD_ID})가 아닙니다"
  SRC="$OLD_HOST"
  status_line "$NEW_HOST"

  for attempt in 1 2 3; do
    [[ "$(replica_field "$NEW_HOST" Replica_SQL_Running)" == "Yes" ]] || die "복제가 실행 중이 아닙니다. Last_IO_Error/Last_SQL_Error를 확인하세요"
    q_db "$NEW_HOST" "CALL mysql.rds_stop_replication;" >/dev/null
    for _ in $(seq 1 30); do
      [[ "$(replica_field "$NEW_HOST" Replica_SQL_Running)" == "No" ]] && break
      sleep 1
    done
    READ_FILE="$(replica_field "$NEW_HOST" Source_Log_File)"
    READ_POS="$(replica_field "$NEW_HOST" Read_Source_Log_Pos)"
    EXEC_FILE="$(replica_field "$NEW_HOST" Relay_Source_Log_File)"
    EXEC_POS="$(replica_field "$NEW_HOST" Exec_Source_Log_Pos)"
    log "시도 ${attempt}: 받은 위치 ${READ_FILE}:${READ_POS}, 실행 위치 ${EXEC_FILE}:${EXEC_POS}"
    if [[ -n "$EXEC_FILE" && "$READ_FILE" == "$EXEC_FILE" && "$READ_POS" == "$EXEC_POS" ]]; then
      break
    fi
    log "받았지만 실행하지 않은 이벤트가 있음 → 복제를 다시 켜서 따라잡은 뒤 다시 멈춤"
    q_db "$NEW_HOST" "CALL mysql.rds_start_replication;" >/dev/null
    sleep 5
    if ((attempt == 3)); then
      die "3회 시도 후에도 받은 위치와 실행 위치가 다릅니다. 복제는 다시 켜 둔 상태입니다"
    fi
  done

  OLD_SIZE="$(q_db "$OLD_HOST" "SHOW BINARY LOGS;" | awk -F'\t' -v f="$EXEC_FILE" '$1 == f {print $2}')"
  [[ -n "$OLD_SIZE" && "$EXEC_POS" -le "$OLD_SIZE" ]] || die "① ${EXEC_FILE}:${EXEC_POS}가 구 DB binlog 목록에 없습니다 (복제는 멈춘 상태, 승격하지 말 것)"

  status_line "$NEW_HOST"
  POS_FILE="${LOG_DIR}/position-1-$(date '+%Y%m%d-%H%M%S').txt"
  printf 'SOURCE_HOST %s\nSOURCE_SERVER_ID %s\nFILE %s\nPOS %s\n' "$SRC" "$SRC_ID" "$EXEC_FILE" "$EXEC_POS" > "$POS_FILE"
  cat <<EOM

=== ① 복제 시작 위치 (구 DB binlog 좌표)
원본(구 DB)            ${SRC} (server_id ${SRC_ID})
Relay_Source_Log_File  ${EXEC_FILE}
Exec_Source_Log_Pos    ${EXEC_POS}
저장                   ${POS_FILE}

=== 다음 단계
1. 진행기록에 ①과 시각 기록 (구 DB binlog retention 안에 3번까지 끝내야 함)
2. Terraform PR: mysql_promote = true → 로컬 plan이 "1 to change (replicate_source_db -> null)"인지 확인 → merge → apply
   aws rds describe-db-instances --db-instance-identifier <신 DB> --query 'DBInstances[0].[DBInstanceStatus,ReadReplicaSourceDBInstanceIdentifier,BackupRetentionPeriod]'
   → available, None, 0보다 큼
3. sudo ${SCRIPT_DIR}/init-replication.sh ${ENV_NAME} start ${NEW_HOST} ${SRC} ${POS_FILE}
EOM
  exit 0
fi

# start
OLD_HOST="${4:-}"
POS_FILE="${5:-}"
[[ -n "$OLD_HOST" && -f "$POS_FILE" ]] || usage
FILE="$(awk '$1=="FILE"{print $2}' "$POS_FILE")"
POS="$(awk '$1=="POS"{print $2}' "$POS_FILE")"
SAVED_SRC="$(awk '$1=="SOURCE_HOST"{print $2}' "$POS_FILE")"
[[ -n "$FILE" && "$POS" =~ ^[0-9]+$ ]] || die "위치 파일 형식 오류: ${POS_FILE}"
[[ "$SAVED_SRC" == "$OLD_HOST" ]] || die "위치 파일의 원본(${SAVED_SRC})과 지정한 구 DB(${OLD_HOST})가 다릅니다"
[[ -z "$(replica_field "$NEW_HOST" Source_Host)" ]] || die "신 DB에 복제 설정이 남아 있습니다. 승격이 끝났는지 확인하세요 (덮어쓰지 않음)"

REPL_PW="$(get_parameter "/lookddak/${ENV_NAME}/rds/repl/password")"
[[ -n "$REPL_PW" ]] || die "repl 비밀번호를 읽지 못했습니다"

log "외부 복제 연결: 신 DB가 구 DB ${FILE}:${POS}부터 복제"
q_db "$NEW_HOST" "CALL mysql.rds_set_external_source('${OLD_HOST}', 3306, 'repl', '${REPL_PW}', '${FILE}', ${POS}, 1); CALL mysql.rds_start_replication;" >/dev/null

for _ in $(seq 1 30); do
  IO="$(replica_field "$NEW_HOST" Replica_IO_Running)"
  SQL="$(replica_field "$NEW_HOST" Replica_SQL_Running)"
  [[ "$IO" == "Yes" && "$SQL" == "Yes" ]] && break
  sleep 1
done
status_line "$NEW_HOST"
SRC_NOW="$(replica_field "$NEW_HOST" Source_Host)"
ERR="$(replica_field "$NEW_HOST" Last_IO_Error)$(replica_field "$NEW_HOST" Last_SQL_Error)"
if [[ "$IO" == "Yes" && "$SQL" == "Yes" && "$SRC_NOW" == "$OLD_HOST" ]]; then
  log "완료: 신 DB가 구 DB를 복제 중 (Yes/Yes). 지연이 0이 되면 verify-sync.sh로 데이터 일치를 확인하세요"
  exit 0
fi
die "외부 복제 확인 실패 (IO=${IO} SQL=${SQL} source=${SRC_NOW} ${ERR})"
