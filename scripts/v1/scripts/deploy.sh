#!/usr/bin/env bash
# EC2 배치 경로: /opt/lookddak/scripts/deploy.sh
# 사용법: deploy.sh <fe|be|ai> <7자리 이미지 태그> [github_run_id]
#
# 1차 테스트 기준:
# - HTTP 애플리케이션 healthcheck 사용 안 함
# - Nginx 외부 smoke test 사용 안 함
# - 컨테이너 실행 상태와 내부 포트만 확인
#
# 종료 코드:
#   0  배포 성공 또는 같은 정상 버전이 이미 실행 중
#   1  새 버전 배포 실패, 서비스 미변경 또는 이전 버전 복구 성공
#   2  이전 버전 복구까지 실패
#   64 입력값 또는 EC2 배포 설정 오류
#   75 다른 배포가 잠금을 사용 중

set -Eeuo pipefail

SERVICE_KEY="${1:-}"
NEW_TAG="${2:-}"
RUN_ID="${3:-manual}"

readonly APP_DIR="/opt/lookddak"
readonly ENV_FILE="${APP_DIR}/.env"
readonly PARAMETER_LOADER="${APP_DIR}/scripts/load-parameters.sh"
readonly LOCK_FILE="/var/lock/lookddak-deploy.lock"
readonly HISTORY_FILE="${APP_DIR}/deploy-history.log"
readonly AWS_REGION="ap-northeast-2"

readonly LOCK_WAIT=60
readonly WAIT_TIMEOUT=150
readonly CHECK_INTERVAL=5

log() {
  echo "[$(date '+%F %T')] [${SERVICE_KEY:-?}] $*"
}

usage() {
  echo "usage: deploy.sh <fe|be|ai> <7-char-tag> [run_id]"
}

fail_config() {
  log "$1"
  exit 64
}

require_command() {
  command -v "$1" >/dev/null 2>&1 \
    || fail_config "필수 명령이 없습니다: $1"
}

env_get() {
  local key="$1"

  grep -E "^${key}=" "$ENV_FILE" \
    | tail -n 1 \
    | cut -d= -f2- || true
}

env_set() {
  local key="$1"
  local value="$2"
  local tmp

  tmp="$(mktemp "${ENV_FILE}.XXXXXX")" || return 1

  grep -vE "^${key}=" "$ENV_FILE" > "$tmp" || true
  echo "${key}=${value}" >> "$tmp" || return 1

  chmod 600 "$tmp" || return 1
  chown root:root "$tmp" || return 1
  mv "$tmp" "$ENV_FILE" || return 1
}

record() {
  local result="$1"

  if ! printf '%s service=%s from=%s to=%s result=%s run=%s\n' \
    "$(date -Is)" \
    "$SERVICE_KEY" \
    "${PREV_TAG:-none}" \
    "$NEW_TAG" \
    "$result" \
    "$RUN_ID" \
    >> "$HISTORY_FILE"; then
    log "경고: 배포 이력을 기록하지 못했습니다."
  fi
}

service_port_ready() {
  local container_id

  container_id="$(docker compose ps -q "$COMPOSE_SERVICE")"
  [[ -n "$container_id" ]] || return 1

  if [[ "$(
    docker inspect \
      --format '{{.State.Running}}' \
      "$container_id" 2>/dev/null
  )" != "true" ]]; then
    return 1
  fi

  docker compose exec \
    -T \
    "$COMPOSE_SERVICE" \
    "${PORT_CHECK_COMMAND[@]}" \
    >/dev/null 2>&1
}

wait_for_service_port() {
  local deadline=$((SECONDS + WAIT_TIMEOUT))

  while ((SECONDS < deadline)); do
    if service_port_ready; then
      log "${COMPOSE_SERVICE} 컨테이너 실행 및 포트 확인 성공"
      return 0
    fi

    sleep "$CHECK_INTERVAL"
  done

  log "${COMPOSE_SERVICE}가 ${WAIT_TIMEOUT}초 안에 준비되지 않았습니다."
  docker compose ps "$COMPOSE_SERVICE" || true
  return 1
}

switch_to() {
  local tag="$1"
  local force_recreate="${2:-false}"
  local -a compose_args

  env_set "$TAG_VAR" "$tag" || return 1

  compose_args=(
    up
    -d
    --no-deps
  )

  if [[ "$force_recreate" == "true" ]]; then
    compose_args+=(--force-recreate)
  fi

  compose_args+=("$COMPOSE_SERVICE")

  log "컨테이너 전환: ${COMPOSE_SERVICE}:${tag}"

  docker compose "${compose_args[@]}" || return 1
  wait_for_service_port
}

show_failure_status() {
  log "실패 시점의 컨테이너 상태"
  docker compose ps "$COMPOSE_SERVICE" || true
  log "상세 로그는 서비스별 CloudWatch Logs에서 확인하세요."
}

cleanup_images() {
  docker images "$IMAGE" --format '{{.Tag}}' \
    | grep -vxE "${NEW_TAG}|${PREV_TAG:-__none__}" \
    | xargs -r -I{} docker rmi "${IMAGE}:{}" \
      >/dev/null 2>&1 || true
}

# -------------------------------------------------------------------
# 1. 배포 대상 결정
# -------------------------------------------------------------------

case "$SERVICE_KEY" in
  fe)
    COMPOSE_SERVICE="nextjs"
    TAG_VAR="NEXTJS_IMAGE_TAG"
    ECR_REPO="lookddak-nextjs"
    PORT_CHECK_COMMAND=(
      node
      -e
      'const net=require("net");const s=net.createConnection({host:"127.0.0.1",port:3000});s.setTimeout(3000);s.on("connect",()=>{s.end();process.exit(0)});s.on("timeout",()=>process.exit(1));s.on("error",()=>process.exit(1));'
    )
    ;;

  be)
    COMPOSE_SERVICE="spring"
    TAG_VAR="SPRING_IMAGE_TAG"
    ECR_REPO="lookddak-spring"
    PORT_CHECK_COMMAND=(
      bash
      -c
      'exec 3<>/dev/tcp/127.0.0.1/8080'
    )
    ;;

  ai)
    COMPOSE_SERVICE="fastapi"
    TAG_VAR="FASTAPI_IMAGE_TAG"
    ECR_REPO="lookddak-fastapi"
    PORT_CHECK_COMMAND=(
      python
      -c
      'import socket; socket.create_connection(("127.0.0.1", 8000), 3).close()'
    )
    ;;

  *)
    usage
    exit 64
    ;;
esac

if [[ ! "$NEW_TAG" =~ ^[0-9a-f]{7}$ ]]; then
  fail_config "이미지 태그는 소문자 7자리 Git SHA여야 합니다."
fi

for command_name in aws docker flock grep cut mktemp xargs python3; do
  require_command "$command_name"
done

[[ "$EUID" -eq 0 ]] \
  || fail_config "deploy.sh는 root 권한으로 실행해야 합니다."

[[ -d "$APP_DIR" ]] \
  || fail_config "애플리케이션 디렉터리가 없습니다: $APP_DIR"

[[ -f "$ENV_FILE" ]] \
  || fail_config "환경 파일이 없습니다: $ENV_FILE"

[[ -f "${APP_DIR}/docker-compose.yaml" ]] \
  || fail_config "docker-compose.yaml이 없습니다."

[[ -f "$PARAMETER_LOADER" ]] \
  || fail_config "load-parameters.sh가 없습니다."

# 현재 deploy.sh 셸에 Parameter Store 공통 함수를 불러온다.
source "$PARAMETER_LOADER"

trap cleanup_runtime_parameters EXIT
trap 'log "예기치 않은 오류로 중단 (line ${LINENO})"' ERR

cd "$APP_DIR"

if ! docker compose version >/dev/null 2>&1; then
  fail_config "Docker Compose 플러그인을 사용할 수 없습니다."
fi

# -------------------------------------------------------------------
# 2. 동시 배포 차단 및 런타임 설정 준비
# -------------------------------------------------------------------

exec 9>"$LOCK_FILE"

log "배포 잠금 대기 (최대 ${LOCK_WAIT}초)"

if ! flock -w "$LOCK_WAIT" 9; then
  log "다른 배포가 진행 중입니다."
  exit 75
fi

log "Parameter Store 런타임 설정 조회"
load_runtime_parameters
log "Parameter Store 런타임 설정 조회 성공"

log "Compose 설정 확인"
docker compose config --quiet

# -------------------------------------------------------------------
# 3. 현재 배포 상태 확인
# -------------------------------------------------------------------

ECR_REGISTRY="$(env_get ECR_REGISTRY)"
PREV_TAG="$(env_get "$TAG_VAR")"

[[ -n "$ECR_REGISTRY" ]] \
  || fail_config ".env의 ECR_REGISTRY 값이 비어 있습니다."

if [[ -n "$PREV_TAG" && ! "$PREV_TAG" =~ ^[0-9a-f]{7}$ ]]; then
  fail_config "${TAG_VAR} 값이 올바른 7자리 SHA가 아닙니다: '$PREV_TAG'"
fi

readonly IMAGE="${ECR_REGISTRY}/${ECR_REPO}"

log "현재 태그=${PREV_TAG:-없음}, 요청 태그=${NEW_TAG}"

FORCE_RECREATE="false"

if [[ "$PREV_TAG" == "$NEW_TAG" ]]; then
  if service_port_ready; then
    log "같은 태그가 이미 정상 실행 중입니다."
    record "skipped-same-tag"
    exit 0
  fi

  log "같은 태그지만 컨테이너 또는 포트가 준비되지 않아 재생성합니다."
  FORCE_RECREATE="true"
fi

# -------------------------------------------------------------------
# 4. 새 이미지와 롤백 이미지 확보
# -------------------------------------------------------------------

log "EC2 인스턴스 역할로 ECR 로그인"

if ! aws ecr get-login-password \
  --region "$AWS_REGION" \
  | docker login \
      --username AWS \
      --password-stdin "$ECR_REGISTRY" \
      >/dev/null; then
  record "ecr-login-failed-service-unchanged"
  log "ECR 로그인 실패. 실행 중인 컨테이너는 변경하지 않았습니다."
  exit 1
fi

log "새 이미지 pull: ${IMAGE}:${NEW_TAG}"

if ! docker pull "${IMAGE}:${NEW_TAG}"; then
  record "new-image-pull-failed-service-unchanged"
  log "새 이미지 pull 실패. 실행 중인 컨테이너는 변경하지 않았습니다."
  exit 1
fi

if [[ -n "$PREV_TAG" && "$PREV_TAG" != "$NEW_TAG" ]]; then
  if ! docker image inspect "${IMAGE}:${PREV_TAG}" >/dev/null 2>&1; then
    log "롤백용 이미지 pull: ${IMAGE}:${PREV_TAG}"

    if ! docker pull "${IMAGE}:${PREV_TAG}"; then
      record "previous-image-pull-failed-service-unchanged"
      log "롤백용 이미지를 확보하지 못해 배포를 시작하지 않습니다."
      exit 1
    fi
  fi
fi

# -------------------------------------------------------------------
# 5. 새 버전 전환 및 포트 확인
# -------------------------------------------------------------------

if switch_to "$NEW_TAG" "$FORCE_RECREATE"; then
  record "success"
  cleanup_images
  log "배포 성공"
  exit 0
fi

show_failure_status

if [[ "$PREV_TAG" == "$NEW_TAG" ]]; then
  record "failed-same-tag-recovery"
  log "같은 태그의 강제 재생성도 실패했습니다."
  exit 2
fi

if [[ -z "$PREV_TAG" ]]; then
  record "failed-no-previous"
  log "되돌아갈 이전 이미지 태그가 없습니다."
  exit 2
fi

# -------------------------------------------------------------------
# 6. 이전 버전 롤백
# -------------------------------------------------------------------

log "이전 태그(${PREV_TAG})로 롤백"

if switch_to "$PREV_TAG" "false"; then
  record "rolled-back"
  log "이전 버전 롤백 성공"
  exit 1
fi

show_failure_status
record "rollback-failed"

log "롤백까지 실패했습니다. 즉시 수동 확인이 필요합니다."
exit 2
