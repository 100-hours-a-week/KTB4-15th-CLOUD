#!/usr/bin/env bash
# EC2 배치 경로: /opt/lookddak/v1-mysql-migration/verify-sync.sh
# 사용법: sudo /opt/lookddak/v1-mysql-migration/verify-sync.sh <dev|prod> <신 DB 엔드포인트>
#
# 역할: 구 DB(현재 ProxySQL 쓰기 대상)와 신 DB(구 DB를 복제 중)의 데이터가 같은지 확인한다. (조회만 함)
#   1. 신 DB 복제 상태 확인 (Yes/Yes, 지연, 에러)
#   2. 구 DB 현재 binlog 위치까지 신 DB가 따라오도록 SOURCE_POS_WAIT
#   3. 테이블별 행 수 + CHECKSUM TABLE 비교
#   4. 불일치 테이블은 한 번 더 따라잡은 뒤 재비교 (그 사이 들어온 쓰기 때문일 수 있음)
#
# 주의: CHECKSUM TABLE은 테이블 전체를 읽는다. 큰 테이블이 있으면 트래픽이 적은 시간에 실행한다.
#
# 종료 코드: 0 일치 / 1 불일치 또는 복제 이상 / 64 입력 오류

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib-mysql-cli.sh
source "${SCRIPT_DIR}/lib-mysql-cli.sh"

ENV_NAME="${1:-}"
NEW_HOST="${2:-}"

[[ "$ENV_NAME" =~ ^(dev|prod)$ && -n "$NEW_HOST" ]] || {
  echo "usage: verify-sync.sh <dev|prod> <new-db-endpoint>"
  exit 64
}

trap stop_cli EXIT

load_credentials "$ENV_NAME"
start_cli

# 구 DB = ProxySQL에서 현재 ONLINE인 쓰기 대상
OLD_HOST="$(q_admin "SELECT hostname FROM runtime_mysql_servers WHERE hostgroup_id=${WRITER_HOSTGROUP} AND status='ONLINE'")"
[[ -n "$OLD_HOST" && "$(wc -l <<<"$OLD_HOST")" -eq 1 ]] || die "ProxySQL ONLINE 쓰기 대상이 하나가 아닙니다: ${OLD_HOST:-없음}"
[[ "$OLD_HOST" != "$NEW_HOST" ]] || die "신 DB가 이미 ProxySQL 쓰기 대상입니다"

log "구 DB: ${OLD_HOST}"
log "신 DB: ${NEW_HOST}"
log "DB:    ${RDS_DATABASE}"

# ---------------------------------------------------------------
# 1. 복제 상태
# ---------------------------------------------------------------
io="$(replica_field "$NEW_HOST" Replica_IO_Running)"
sql="$(replica_field "$NEW_HOST" Replica_SQL_Running)"
lag="$(replica_field "$NEW_HOST" Seconds_Behind_Source)"
src="$(replica_field "$NEW_HOST" Source_Host)"
log "복제: IO=${io} SQL=${sql} lag=${lag} source=${src}"

[[ "$io" == "Yes" && "$sql" == "Yes" ]] || die "신 DB 복제가 실행 중이 아닙니다 (Last_IO_Error/Last_SQL_Error 확인)"
[[ "$src" == "$OLD_HOST" ]] || die "신 DB의 복제 원본(${src})이 ProxySQL 쓰기 대상(${OLD_HOST})과 다릅니다"

catch_up() {
  local pos file p result
  pos="$(binlog_position "$OLD_HOST")"
  file="${pos%%$'\t'*}"
  p="${pos##*$'\t'}"
  result="$(q_db "$NEW_HOST" "SELECT SOURCE_POS_WAIT('${file}', ${p}, 30)")"
  log "따라잡기: 구 DB ${file}:${p} → SOURCE_POS_WAIT=${result}"
  [[ "$result" != "NULL" && "$result" -ge 0 ]] || die "신 DB가 30초 안에 따라잡지 못했습니다"
}

# ---------------------------------------------------------------
# 2~3. 따라잡은 뒤 테이블별 비교
# ---------------------------------------------------------------
TABLES="$(q_db "$OLD_HOST" "SELECT table_name FROM information_schema.tables WHERE table_schema='${RDS_DATABASE}' AND table_type='BASE TABLE' ORDER BY table_name")"
[[ -n "$TABLES" ]] || die "${RDS_DATABASE}에 테이블이 없습니다"

compare_table() {
  local t="$1" oc nc os ns
  oc="$(q_db "$OLD_HOST" "SELECT COUNT(*) FROM \`${RDS_DATABASE}\`.\`${t}\`")"
  nc="$(q_db "$NEW_HOST" "SELECT COUNT(*) FROM \`${RDS_DATABASE}\`.\`${t}\`")"
  os="$(q_db "$OLD_HOST" "CHECKSUM TABLE \`${RDS_DATABASE}\`.\`${t}\`" | awk -F'\t' '{print $2}')"
  ns="$(q_db "$NEW_HOST" "CHECKSUM TABLE \`${RDS_DATABASE}\`.\`${t}\`" | awk -F'\t' '{print $2}')"
  printf '%-40s rows %10s / %-10s checksum %12s / %-12s %s\n' \
    "$t" "$oc" "$nc" "$os" "$ns" "$([[ "$oc" == "$nc" && "$os" == "$ns" ]] && echo OK || echo DIFF)"
  [[ "$oc" == "$nc" && "$os" == "$ns" ]]
}

catch_up

log "테이블 비교 (구 / 신)"
MISMATCH=()
while read -r t; do
  compare_table "$t" || MISMATCH+=("$t")
done <<<"$TABLES"

# ---------------------------------------------------------------
# 4. 불일치 재확인
# ---------------------------------------------------------------
if ((${#MISMATCH[@]} > 0)); then
  log "불일치 ${#MISMATCH[@]}개. 비교 중 들어온 쓰기일 수 있어 다시 따라잡은 뒤 재비교"
  catch_up
  STILL=()
  for t in "${MISMATCH[@]}"; do
    compare_table "$t" || STILL+=("$t")
  done

  if ((${#STILL[@]} > 0)); then
    log "결과: 불일치 ${#STILL[@]}개 → ${STILL[*]}"
    log "쓰기가 계속 들어오는 테이블이면 트래픽이 적을 때 다시 실행하세요. 계속 다르면 복제 위치·필터를 확인합니다."
    exit 1
  fi
fi

log "결과: 테이블 $(wc -l <<<"$TABLES")개 모두 일치"
