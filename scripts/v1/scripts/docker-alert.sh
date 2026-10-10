#!/bin/bash
# 컨테이너 상태 변화를 EventBridge로 전송 (→ SQS → Lambda → Discord)
#
# 알림 종류
#   DOWN       비정상 종료 (exit 0, 143 외)       + 마지막 로그
#   OOM        메모리 한도 초과
#   UNHEALTHY  헬스체크 연속 실패                 + 마지막 로그
#   STOP       정상 중지 (배포 교체, docker stop)
#   START      기동 (이미지 태그 포함)
#   HEALTHY    기동 또는 unhealthy 이후 정상 확인
#
# - 같은 컨테이너·같은 종류의 알림은 COOLDOWN 동안 한 번만 전송 (재시작 반복 시 폭주 방지)
# - docker compose 재배포 때 기존 컨테이너가 "<id>_<이름>"으로 바뀌는 경우도 원래 이름으로 처리
# - EventBridge 전송이 실패하면 최대 3번 재시도
#
# 필요 권한 (EC2 IAM 역할)
#   events:PutEvents  on  arn:aws:events:ap-northeast-2:<계정ID>:event-bus/default

set -u
export PATH=$PATH:/snap/bin:/usr/local/bin

# ── 설정 ────────────────────────────────────────────────────
REGION="ap-northeast-2"
EVENT_SOURCE="custom.docker"
DETAIL_TYPE="Container State Change"
PREFIX="lookddak-"   # 감시할 컨테이너 이름 접두어 (빈 값이면 모든 컨테이너)
COOLDOWN=300         # 같은 알림 재전송 간격 (초)
LOG_LINES=15         # 첨부할 로그 줄 수 (0이면 첨부 안 함)
HOST=$(hostname)
# ────────────────────────────────────────────────────────────

# EventBridge로 이벤트 1건 전송 (kind, container, exit_code, image, message, logs)
put_event() {
  local entries attempt failed
  entries=$(python3 -c '
import json, sys
from datetime import datetime, timezone
kind, name, code, image, message, logs, host, source, dtype = sys.argv[1:10]
detail = {
    "kind": kind,
    "container": name,
    "exitCode": code,
    "image": image,
    "message": message,
    "logs": logs,
    "host": host,
    "time": datetime.now(timezone.utc).isoformat(timespec="seconds"),
}
print(json.dumps([{"Source": source, "DetailType": dtype, "Detail": json.dumps(detail, ensure_ascii=False)}]))
' "$1" "$2" "$3" "$4" "$5" "$6" "$HOST" "$EVENT_SOURCE" "$DETAIL_TYPE")

  for attempt in 1 2 3; do
    failed=$(aws events put-events --region "$REGION" --entries "$entries" \
      --query FailedEntryCount --output text 2>&1)
    [[ "$failed" == "0" ]] && { echo "ok"; return 0; }
    sleep $((attempt * 2))
  done
  echo "failed: $failed"
  return 1
}

exit_meaning() {
  case "$1" in
    0)   echo "정상 종료" ;;
    1)   echo "애플리케이션 에러" ;;
    3)   echo "JVM OutOfMemoryError (ExitOnOutOfMemoryError)" ;;
    137) echo "강제 종료 (SIGKILL, OOM 가능성)" ;;
    139) echo "Segmentation fault" ;;
    143) echo "정상 중지 요청 (SIGTERM, 배포 교체 또는 docker stop)" ;;
    *)   echo "비정상 종료" ;;
  esac
}

container_logs() {  # 컨테이너 ID
  (( LOG_LINES > 0 )) || return 0
  docker logs --tail "$LOG_LINES" "$1" 2>&1 | tail -c 1500
}

declare -A LAST_SENT       # 알림 종류별 마지막 전송 시각
declare -A WAIT_HEALTHY    # START 또는 UNHEALTHY 이후 healthy 확인 대기 중인 컨테이너

docker events \
  --filter type=container \
  --filter event=start \
  --filter event=die \
  --filter event=oom \
  --filter event=health_status \
  --format '{{.Action}}|{{.Actor.Attributes.name}}|{{.Actor.Attributes.exitCode}}|{{.Actor.Attributes.image}}|{{.Actor.ID}}' |
while IFS='|' read -r action name code image cid; do
  # compose 재배포 시 기존 컨테이너는 "<12자리 id>_<이름>"으로 바뀐 뒤 중지됨 → 원래 이름으로
  if [[ "$name" =~ ^[0-9a-f]{12}_(.+)$ ]]; then
    name=${BASH_REMATCH[1]}
  fi
  [[ -z "$PREFIX" || "$name" == "$PREFIX"* ]] || continue

  logs=""
  case "$action" in
    start)
      kind="START"
      message="컨테이너 기동"
      WAIT_HEALTHY[$name]=1
      ;;
    die)
      if [[ "$code" == "0" || "$code" == "143" ]]; then
        kind="STOP"
        message="exit code $code ($(exit_meaning "$code"))"
      else
        kind="DOWN"
        restarts=$(docker inspect -f '{{.RestartCount}}' "$cid" 2>/dev/null || echo "?")
        message="exit code $code ($(exit_meaning "$code")), 재시작 누적 ${restarts}회"
        logs=$(container_logs "$cid")
      fi
      ;;
    oom)
      kind="OOM"
      message="컨테이너 메모리 한도 초과로 프로세스가 종료됨"
      ;;
    "health_status: unhealthy")
      kind="UNHEALTHY"
      message="헬스체크 연속 실패 (프로세스는 떠 있지만 응답 없음)"
      logs=$(container_logs "$cid")
      WAIT_HEALTHY[$name]=1
      ;;
    "health_status: healthy")
      [[ -n "${WAIT_HEALTHY[$name]:-}" ]] || continue
      unset "WAIT_HEALTHY[$name]"
      kind="HEALTHY"
      message="헬스체크 통과, 정상 서비스 중"
      ;;
    *)
      continue
      ;;
  esac

  # 같은 알림은 COOLDOWN 동안 한 번만
  key="$name:$kind"
  now=$(date +%s)
  if (( now - ${LAST_SENT[$key]:-0} < COOLDOWN )); then
    echo "$(date -Is) [$kind] $name (cooldown, skipped)"
    continue
  fi
  LAST_SENT[$key]=$now

  result=$(put_event "$kind" "$name" "$code" "${image##*/}" "$message" "$logs")
  echo "$(date -Is) [$kind] $name -> $result"
done
