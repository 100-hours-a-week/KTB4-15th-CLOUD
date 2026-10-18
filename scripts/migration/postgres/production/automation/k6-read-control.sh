#!/usr/bin/env bash
# 운영 PostgreSQL 전환 중 10 RPS 읽기 관찰용 k6 컨테이너를 제어한다.
set -Eeuo pipefail
set +x

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common-functions.sh
source "${ROOT}/common-functions.sh"

ACTION="${1:-}"
RUN_ID="${2:-}"
readonly K6_IMAGE="${K6_IMAGE:-grafana/k6:1.3.0@sha256:3ddc8b1a33a2c3d8edc6e99b6a762ae36cba08788463458f5e6a7703e14eb77d}"
readonly K6_AUTH_FILE="${K6_AUTH_FILE:-${APP_DIR}/k6.prod.auth}"
readonly K6_AUTH_KIND="${K6_AUTH_KIND:-cookie}"
readonly K6_BASE_URL="${K6_BASE_URL:-https://lookddak.com}"
readonly K6_READ_PATH="${K6_READ_PATH:-/api/v1/chat-rooms}"
readonly K6_DURATION="${K6_DURATION:-10m}"
readonly K6_RATE=10
readonly K6_SCRIPT_DIR="${PRODUCTION_MIGRATION_ROOT}/workload/k6"
readonly K6_SCRIPT="${K6_SCRIPT_DIR}/read-observer.js"
readonly RESULT_DIR="${RESULT_ROOT}/${RUN_ID}/k6"
readonly CONTAINER_NAME="lookddak-k6-${RUN_ID}"

usage() {
  printf '사용법: %s {prepare|check|start|status|stop|finish} <작업-ID>\n' "$(basename "$0")"
}

case "$ACTION" in
  prepare|check|start|status|stop|finish) ;;
  *) usage; exit 2 ;;
esac

require_run_id "$RUN_ID"
require_root
require_commands docker find install jq

assert_auth_file() {
  test -s "$K6_AUTH_FILE" || die "k6 인증정보 파일이 없거나 비어 있습니다: $K6_AUTH_FILE"
  [[ -z "$(find "$K6_AUTH_FILE" -perm /077 -print -quit)" ]] \
    || die "k6 인증정보 파일은 group/other 권한이 없어야 합니다: chmod 600 $K6_AUTH_FILE"
  [[ "$K6_AUTH_KIND" == "cookie" || "$K6_AUTH_KIND" == "bearer" ]] \
    || die "K6_AUTH_KIND는 cookie 또는 bearer여야 합니다"
}

container_exists() {
  docker inspect "$CONTAINER_NAME" >/dev/null 2>&1
}

container_running() {
  [[ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER_NAME" 2>/dev/null || true)" == "true" ]]
}

if [[ "$ACTION" == "prepare" ]]; then
  acquire_migration_lock
  docker pull "$K6_IMAGE"
  docker run --rm --network none --read-only --cap-drop ALL \
    --security-opt no-new-privileges "$K6_IMAGE" version
  log "K6_IMAGE_READY image=$K6_IMAGE"
  exit 0
fi

test -f "$K6_SCRIPT" || die "k6 스크립트가 없습니다: $K6_SCRIPT"
assert_auth_file

if [[ "$ACTION" == "check" ]]; then
  docker image inspect "$K6_IMAGE" >/dev/null 2>&1 \
    || die "k6 이미지가 없습니다. prepare를 먼저 실행하세요: $K6_IMAGE"
  [[ "$K6_BASE_URL" == "https://lookddak.com" ]] \
    || die "운영 전환 검증 대상은 https://lookddak.com 이어야 합니다"
  [[ "$K6_READ_PATH" == /* ]] || die "K6_READ_PATH는 /로 시작해야 합니다"
  [[ "$K6_DURATION" =~ ^[1-9][0-9]*(s|m|h)$ ]] || die "K6_DURATION 형식이 올바르지 않습니다"
  log "K6_CHECK_SUCCEEDED target=${K6_BASE_URL}${K6_READ_PATH} rate=${K6_RATE} duration=${K6_DURATION} auth_kind=${K6_AUTH_KIND}"
  exit 0
fi

if [[ "$ACTION" == "status" ]]; then
  container_exists || die "k6 컨테이너가 없습니다: $CONTAINER_NAME"
  docker inspect -f 'status={{.State.Status}} exit_code={{.State.ExitCode}} started={{.State.StartedAt}} finished={{.State.FinishedAt}}' "$CONTAINER_NAME"
  docker logs --tail 30 "$CONTAINER_NAME" 2>&1 || true
  exit 0
fi

if [[ "$ACTION" == "stop" ]]; then
  container_exists || die "k6 컨테이너가 없습니다: $CONTAINER_NAME"
  if container_running; then
    docker stop --time 10 "$CONTAINER_NAME" >/dev/null
    log "K6_STOPPED container=$CONTAINER_NAME"
  else
    log "K6_ALREADY_STOPPED container=$CONTAINER_NAME"
  fi
  exit 0
fi

if [[ "$ACTION" == "finish" ]]; then
  container_exists || die "k6 컨테이너가 없습니다: $CONTAINER_NAME"
  container_running && die "k6가 아직 실행 중입니다"
  exit_code="$(docker inspect -f '{{.State.ExitCode}}' "$CONTAINER_NAME")"
  docker logs "$CONTAINER_NAME" > "${RESULT_DIR}/k6.log" 2>&1
  [[ "$exit_code" == "0" ]] || die "k6 검증이 실패했습니다: exit_code=$exit_code log=${RESULT_DIR}/k6.log"
  test -s "${RESULT_DIR}/summary.json" || die "k6 summary가 없습니다"
  jq '{checks:.metrics.checks.values.rate,http_req_failed:.metrics.http_req_failed.values.rate,p99_ms:.metrics.http_req_duration.values["p(99)"],dropped:.metrics.dropped_iterations.values.count,server_errors:.metrics.server_errors.values.count,transport_errors:.metrics.transport_errors.values.count}' \
    "${RESULT_DIR}/summary.json"
  log "K6_FINISHED run_id=$RUN_ID rate=$K6_RATE result=${RESULT_DIR}"
  exit 0
fi

acquire_migration_lock
docker image inspect "$K6_IMAGE" >/dev/null 2>&1 \
  || die "k6 이미지가 없습니다. prepare를 먼저 실행하세요: $K6_IMAGE"
! container_exists || die "같은 작업 ID의 k6 컨테이너가 이미 있습니다: $CONTAINER_NAME"
install -d -o root -g root -m 0750 "$RESULT_DIR"

docker run --detach \
  --name "$CONTAINER_NAME" \
  --network bridge \
  --read-only \
  --user 0:0 \
  --cap-drop ALL \
  --security-opt no-new-privileges \
  --cpus 0.50 \
  --memory 256m \
  --pids-limit 128 \
  --tmpfs /tmp:size=32m,mode=1777 \
  --volume "${K6_SCRIPT_DIR}:/scripts:ro" \
  --volume "${K6_AUTH_FILE}:/run/secrets/k6-auth:ro" \
  --volume "${RESULT_DIR}:/results" \
  --env "BASE_URL=${K6_BASE_URL}" \
  --env "READ_PATH=${K6_READ_PATH}" \
  --env "RATE=${K6_RATE}" \
  --env "DURATION=${K6_DURATION}" \
  --env "RUN_ID=${RUN_ID}" \
  --env "AUTH_KIND=${K6_AUTH_KIND}" \
  --env "AUTH_SECRET_FILE=/run/secrets/k6-auth" \
  "$K6_IMAGE" run --summary-export=/results/summary.json /scripts/read-observer.js >/dev/null

sleep 2
container_running || {
  docker logs "$CONTAINER_NAME" 2>&1 || true
  die "k6 시작에 실패했습니다"
}
log "K6_STARTED container=$CONTAINER_NAME target=${K6_BASE_URL}${K6_READ_PATH} rate=${K6_RATE} duration=${K6_DURATION}"
