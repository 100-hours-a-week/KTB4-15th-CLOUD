#!/usr/bin/env bash
# EC2 배치 경로: /opt/lookddak/v1-mysql-migration/check-integrity.sh
# 사용법:
#   부하 전 시작값: sudo ./check-integrity.sh <dev|prod> <구 DB> <신 DB> --start [상품 id=1]
#   부하 후 판정:   sudo ./check-integrity.sh <dev|prod> <구 DB> <신 DB> <expected.txt> <click_count 시작값> [상품 id=1]
#   (verify-sync.sh로 복제가 따라잡은 것을 확인한 뒤 실행)
#
# 역할: 부하 리허설이 끝난 뒤, k6가 "성공 응답을 받았다"고 기록한 쓰기가 두 DB에 그대로 있는지 확인한다. (조회만 함)
#   expected.txt = 부하 머신에서 analyze.py가 출력한 "정합성 기대값" 블록
#     CLICKS_OK <2xx 클릭 수>
#     CLICKS_NOT_OK <실패·타임아웃 클릭 수>
#     ROOM <채팅방 id> <마지막 성공 제목> <그보다 나중에 실패한 제목들(쉼표) 또는 ->
#
# 판정
#   채팅방 제목 (VU 하나가 자기 채팅방만 순서대로 바꾸므로 마지막 성공 제목 = DB 최종 값이어야 함)
#     OK        DB 값 = 마지막 성공 제목
#     결과불명  DB 값 = 나중에 실패로 받은 제목 (실패 응답을 받았지만 실제로는 반영됨)
#     불일치    그 외 (성공 응답을 받은 쓰기가 사라졌거나 다른 값이 섞임)
#   클릭 카운터 (증가량 = click_count - 시작값)
#     OK        증가량 = CLICKS_OK
#     결과불명  CLICKS_OK < 증가량 <= CLICKS_OK + CLICKS_NOT_OK
#     유실      증가량 < CLICKS_OK
#     초과      증가량 > CLICKS_OK + CLICKS_NOT_OK (중복 적용)
#   두 DB      제목·클릭 수가 서로 같아야 함 (복제 일치)
#
# 종료 코드: 0 정합성 이상 없음(결과불명은 경고) / 1 불일치·유실·초과·두 DB 차이 / 64 입력 오류

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib-mysql-cli.sh
source "${SCRIPT_DIR}/lib-mysql-cli.sh"

ENV_NAME="${1:-}"
OLD_HOST="${2:-}"
NEW_HOST="${3:-}"

if [[ "${4:-}" == "--start" ]]; then
  PRODUCT_ID="${5:-1}"
  [[ "$ENV_NAME" =~ ^(dev|prod)$ && -n "$OLD_HOST" && -n "$NEW_HOST" && "$PRODUCT_ID" =~ ^[0-9]+$ ]] || { echo "usage: check-integrity.sh <dev|prod> <old-db> <new-db> --start [product-id]"; exit 64; }
  trap stop_cli EXIT
  load_credentials "$ENV_NAME"
  start_cli
  for h in "$OLD_HOST" "$NEW_HOST"; do
    log "${h}: product ${PRODUCT_ID} click_count = $(q_db "$h" "SELECT click_count FROM \`${RDS_DATABASE}\`.product WHERE id = ${PRODUCT_ID}")"
  done
  log "쓰기 대상 DB의 값을 시작값으로 기록하세요 (두 값이 같아야 정상)"
  exit 0
fi

EXPECTED="${4:-}"
CLICK_START="${5:-}"
PRODUCT_ID="${6:-1}"

[[ "$ENV_NAME" =~ ^(dev|prod)$ && -n "$OLD_HOST" && -n "$NEW_HOST" && -f "$EXPECTED" && "$CLICK_START" =~ ^[0-9]+$ && "$PRODUCT_ID" =~ ^[0-9]+$ ]] || {
  echo "usage: check-integrity.sh <dev|prod> <old-db> <new-db> <expected.txt> <click-start> [product-id]"
  exit 64
}

trap stop_cli EXIT
load_credentials "$ENV_NAME"
start_cli

CLICKS_OK="$(awk '$1=="CLICKS_OK"{print $2}' "$EXPECTED")"
CLICKS_NOT_OK="$(awk '$1=="CLICKS_NOT_OK"{print $2}' "$EXPECTED")"
ROOM_IDS="$(awk '$1=="ROOM"{print $2}' "$EXPECTED" | paste -sd, -)"
[[ "$CLICKS_OK" =~ ^[0-9]+$ && "$CLICKS_NOT_OK" =~ ^[0-9]+$ && -n "$ROOM_IDS" ]] || { echo "expected.txt 형식 오류"; exit 64; }
[[ "$ROOM_IDS" =~ ^[0-9,]+$ ]] || { echo "채팅방 id 형식 오류"; exit 64; }

FAIL=0
WARN=0

declare -A TITLE_OLD TITLE_NEW
read_titles() {
  local host="$1"
  local -n map="$2"
  while IFS=$'\t' read -r id title; do
    # shellcheck disable=SC2034  # nameref로 호출자의 배열을 채운다
    [[ -n "$id" ]] && map["$id"]="$title"
  done < <(q_db "$host" "SELECT id, title FROM \`${RDS_DATABASE}\`.chat_room WHERE id IN (${ROOM_IDS})")
}
read_titles "$OLD_HOST" TITLE_OLD
read_titles "$NEW_HOST" TITLE_NEW
CLICK_OLD="$(q_db "$OLD_HOST" "SELECT click_count FROM \`${RDS_DATABASE}\`.product WHERE id = ${PRODUCT_ID}")"
CLICK_NEW="$(q_db "$NEW_HOST" "SELECT click_count FROM \`${RDS_DATABASE}\`.product WHERE id = ${PRODUCT_ID}")"

log "구 DB: ${OLD_HOST}"
log "신 DB: ${NEW_HOST}"
echo
echo "== 채팅방 제목 (마지막 성공 / 구 DB / 신 DB)"
while read -r tag room last_ok later_failed; do
  [[ "$tag" == "ROOM" ]] || continue
  line="room ${room}: ${last_ok} / ${TITLE_OLD[$room]:-(없음)} / ${TITLE_NEW[$room]:-(없음)}"
  verdict=""
  for side in OLD NEW; do
    if [[ "$side" == OLD ]]; then v="${TITLE_OLD[$room]:-}"; else v="${TITLE_NEW[$room]:-}"; fi
    if [[ "$v" == "$last_ok" ]]; then
      :
    elif [[ "$later_failed" != "-" && ",${later_failed}," == *",${v},"* ]]; then
      verdict+=" ${side}:결과불명"
      WARN=1
    else
      verdict+=" ${side}:불일치"
      FAIL=1
    fi
  done
  if [[ "${TITLE_OLD[$room]:-x}" != "${TITLE_NEW[$room]:-y}" ]]; then
    verdict+=" 두DB차이"
    FAIL=1
  fi
  echo "  ${line}  →${verdict:- OK}"
done < "$EXPECTED"

echo
echo "== 클릭 카운터 (상품 ${PRODUCT_ID}, 시작값 ${CLICK_START}, clicks_ok ${CLICKS_OK}, clicks_not_ok ${CLICKS_NOT_OK})"
for side in OLD NEW; do
  if [[ "$side" == OLD ]]; then c="$CLICK_OLD"; label="구 DB"; else c="$CLICK_NEW"; label="신 DB"; fi
  [[ "$c" =~ ^[0-9]+$ ]] || { echo "  ${label}: click_count 조회 실패 (${c:-빈 값})"; FAIL=1; continue; }
  delta=$((c - CLICK_START))
  if ((delta == CLICKS_OK)); then
    v="OK"
  elif ((delta > CLICKS_OK && delta <= CLICKS_OK + CLICKS_NOT_OK)); then
    v="결과불명 $((delta - CLICKS_OK))건 (실패로 받았지만 반영)"
    WARN=1
  elif ((delta < CLICKS_OK)); then
    v="유실 $((CLICKS_OK - delta))건 (성공 응답을 받았지만 DB에 없음)"
    FAIL=1
  else
    v="초과 $((delta - CLICKS_OK - CLICKS_NOT_OK))건 (요청보다 많이 반영됨)"
    FAIL=1
  fi
  echo "  ${label}: click_count=${c}, 증가량=${delta} → ${v}"
done
if [[ "$CLICK_OLD" != "$CLICK_NEW" ]]; then
  echo "  두 DB의 click_count가 다름 (${CLICK_OLD} / ${CLICK_NEW})"
  FAIL=1
fi

echo
if ((FAIL)); then
  log "결과: 정합성 이상 있음 (불일치·유실·초과·두 DB 차이). observe.sh report와 cutover 로그를 함께 확인하세요."
  exit 1
fi
if ((WARN)); then
  log "결과: 데이터 유실·불일치 없음. 단, 실패 응답을 받았지만 반영된 쓰기(결과불명)가 있음 → k6 실패 시각과 cutover 단계 확인"
  exit 0
fi
log "결과: 정합성 이상 없음 (제목·클릭 수 모두 기대값과 같고 두 DB 일치)"
