#!/usr/bin/env bash
# EC2 배치 경로: /opt/lookddak/v1-mysql-migration/deploy-proxysql.sh
# 사용법: sudo /opt/lookddak/v1-mysql-migration/deploy-proxysql.sh <7자리 Spring 이미지 태그>
#
# V1 MySQL 무중단 마이그레이션 전용 (다른 작업과 분리). 원본 deploy.sh, docker-compose.yaml은 수정하지 않는다.
#
# 역할: ProxySQL과 Spring을 함께 기동해 Spring이 ProxySQL(proxysql:6033)을 거쳐 RDS에 접속하게 한다.
#
# 동작 순서
#   1. .env의 COMPOSE_FILE 뒤에 v1-mysql-migration/docker-compose.proxysql.yaml을 붙여 이 스크립트 안에서만 사용
#      (.env의 COMPOSE_FILE은 바꾸지 않는다)
#   2. Parameter Store 런타임 값 조회 (DB 계정 등, deploy.sh와 같은 방식)
#   3. ProxySQL 기동 → healthy 대기 → 앱 계정으로 ProxySQL 경유 접속 확인
#   4. Spring을 요청 태그로 재생성 → 8080 포트 확인
#   5. 실패 시 Spring을 이전 태그 + RDS 직접 연결로 되돌림 (ProxySQL은 원인 확인용으로 남김)
#
# 전제
#   - /opt/lookddak/v1-mysql-migration/docker-compose.proxysql.yaml
#   - proxysql.cnf (.env의 PROXYSQL_CNF_PATH, 기본 /opt/lookddak/v1-mysql-migration/proxysql.cnf)
#   - /opt/lookddak/scripts/load-parameters.sh (원본 그대로 사용)
#
# 주의
#   - .env의 COMPOSE_FILE에 docker-compose.proxysql.yaml이 없으면,
#     이후 deploy.sh be 배포는 Spring을 다시 RDS 직접 연결로 재생성한다.
#
# 종료 코드:
#   0  성공
#   1  실패, Spring을 이전 상태로 복구함
#   2  이전 상태 복구까지 실패
#   64 입력값 또는 EC2 설정 오류
#   75 다른 배포가 잠금을 사용 중

set -Eeuo pipefail

NEW_TAG="${1:-}"

readonly APP_DIR="/opt/lookddak"
readonly ENV_FILE="${APP_DIR}/.env"
readonly PARAMETER_LOADER="${APP_DIR}/scripts/load-parameters.sh"
readonly MIGRATION_DIR="${APP_DIR}/v1-mysql-migration"
# COMPOSE_FILE 항목은 프로젝트 디렉터리(/opt/lookddak) 기준 상대 경로
readonly PROXYSQL_COMPOSE="v1-mysql-migration/docker-compose.proxysql.yaml"
readonly LOCK_FILE="/var/lock/lookddak-deploy.lock"
readonly HISTORY_FILE="${APP_DIR}/deploy-history.log"
readonly AWS_REGION="ap-northeast-2"
readonly TAG_VAR="SPRING_IMAGE_TAG"
readonly MYSQL_CLIENT_IMAGE="${MYSQL_CLIENT_IMAGE:-mysql:8.4}"

readonly LOCK_WAIT=60
readonly PROXYSQL_WAIT_TIMEOUT=60
readonly SPRING_WAIT_TIMEOUT=150
readonly CHECK_INTERVAL=5

log() {
  echo "[$(date '+%F %T')] [proxysql+spring] $*"
}

usage() {
  echo "usage: deploy-proxysql.sh <7-char-spring-tag>"
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

  if ! printf '%s service=be-proxysql from=%s to=%s result=%s run=manual\n' \
    "$(date -Is)" \
    "${PREV_TAG:-none}" \
    "$NEW_TAG" \
    "$result" \
    >> "$HISTORY_FILE"; then
    log "경고: 배포 이력을 기록하지 못했습니다."
  fi
}

# ProxySQL healthcheck가 healthy가 될 때까지 기다린다.
wait_for_proxysql() {
  local deadline=$((SECONDS + PROXYSQL_WAIT_TIMEOUT))
  local container_id
  local status

  while ((SECONDS < deadline)); do
    container_id="$(docker compose ps -q proxysql)"

    if [[ -n "$container_id" ]]; then
      status="$(
        docker inspect \
          --format '{{if .State.Health}}{{.State.Health.Status}}{{end}}' \
          "$container_id" 2>/dev/null || true
      )"

      if [[ "$status" == "healthy" ]]; then
        log "ProxySQL healthy"
        return 0
      fi
    fi

    sleep "$CHECK_INTERVAL"
  done

  log "ProxySQL이 ${PROXYSQL_WAIT_TIMEOUT}초 안에 healthy가 되지 않았습니다."
  docker compose ps proxysql || true
  docker compose logs --tail 50 proxysql || true
  return 1
}

# 앱 계정으로 ProxySQL 경유 접속을 확인한다. (Spring을 바꾸기 전 사전 확인)
# 6033은 호스트에 열지 않았으므로 ProxySQL과 같은 네트워크에 임시 클라이언트 컨테이너를 붙인다.
check_proxysql_login() {
  local container_id
  local network

  container_id="$(docker compose ps -q proxysql)"
  network="$(
    docker inspect \
      --format '{{range $name, $_ := .NetworkSettings.Networks}}{{$name}}{{"\n"}}{{end}}' \
      "$container_id" \
      | grep -E 'mysql-network$' \
      | head -n 1 || true
  )"

  [[ -n "$network" ]] || {
    log "ProxySQL 네트워크를 찾지 못했습니다."
    return 1
  }

  log "앱 계정으로 ProxySQL 경유 접속 확인 (network=${network})"

  # 비밀번호는 명령 인자가 아니라 환경 변수(MYSQL_PWD)로 넘긴다.
  if ! MYSQL_PWD="$DB_PASSWORD" docker run \
    --rm \
    --pull missing \
    --network "$network" \
    -e MYSQL_PWD \
    "$MYSQL_CLIENT_IMAGE" \
    mysql \
      -h proxysql \
      -P 6033 \
      -u "$DB_USERNAME" \
      --ssl-mode=REQUIRED \
      --connect-timeout=10 \
      -N -e "SELECT CONCAT('connected: ', @@hostname, ' / ', NOW());"; then
    log "ProxySQL 경유 접속 실패 (proxysql.cnf의 mysql_users, mysql_servers, TLS 설정 확인)"
    docker compose logs --tail 50 proxysql || true
    return 1
  fi
}

spring_port_ready() {
  local container_id

  container_id="$(docker compose ps -q spring)"
  [[ -n "$container_id" ]] || return 1

  [[ "$(
    docker inspect --format '{{.State.Running}}' "$container_id" 2>/dev/null
  )" == "true" ]] || return 1

  docker compose exec -T spring \
    bash -c 'exec 3<>/dev/tcp/127.0.0.1/8080' \
    >/dev/null 2>&1
}

wait_for_spring() {
  local deadline=$((SECONDS + SPRING_WAIT_TIMEOUT))

  while ((SECONDS < deadline)); do
    if spring_port_ready; then
      log "Spring 컨테이너 실행 및 8080 포트 확인 성공"
      return 0
    fi

    sleep "$CHECK_INTERVAL"
  done

  log "Spring이 ${SPRING_WAIT_TIMEOUT}초 안에 준비되지 않았습니다."
  docker compose ps spring || true
  return 1
}

# 주어진 COMPOSE_FILE과 태그로 Spring을 재생성한다.
recreate_spring() {
  local compose_file="$1"
  local tag="$2"

  env_set "$TAG_VAR" "$tag" || return 1

  log "Spring 재생성: tag=${tag}, COMPOSE_FILE=${compose_file}"

  COMPOSE_FILE="$compose_file" docker compose up \
    -d \
    --no-deps \
    --force-recreate \
    spring || return 1

  COMPOSE_FILE="$compose_file" wait_for_spring
}

# -------------------------------------------------------------------
# 1. 입력값과 실행 환경 확인
# -------------------------------------------------------------------

if [[ ! "$NEW_TAG" =~ ^[0-9a-f]{7}$ ]]; then
  usage
  fail_config "이미지 태그는 소문자 7자리 Git SHA여야 합니다."
fi

for command_name in aws docker flock grep cut mktemp python3; do
  require_command "$command_name"
done

[[ "$EUID" -eq 0 ]] \
  || fail_config "deploy-proxysql.sh는 root 권한으로 실행해야 합니다."

[[ -f "$ENV_FILE" ]] \
  || fail_config "환경 파일이 없습니다: $ENV_FILE"

[[ -f "${APP_DIR}/docker-compose.yaml" ]] \
  || fail_config "docker-compose.yaml이 없습니다."

[[ -f "${APP_DIR}/${PROXYSQL_COMPOSE}" ]] \
  || fail_config "${PROXYSQL_COMPOSE}가 없습니다."

[[ -f "$PARAMETER_LOADER" ]] \
  || fail_config "load-parameters.sh가 없습니다."

PROXYSQL_CNF_PATH="$(env_get PROXYSQL_CNF_PATH)"
PROXYSQL_CNF_PATH="${PROXYSQL_CNF_PATH:-${MIGRATION_DIR}/proxysql.cnf}"

[[ -f "$PROXYSQL_CNF_PATH" ]] \
  || fail_config "proxysql.cnf가 없습니다: ${PROXYSQL_CNF_PATH}"

source "$PARAMETER_LOADER"

trap cleanup_runtime_parameters EXIT
trap 'log "예기치 않은 오류로 중단 (line ${LINENO})"' ERR

cd "$APP_DIR"

docker compose version >/dev/null 2>&1 \
  || fail_config "Docker Compose 플러그인을 사용할 수 없습니다."

# -------------------------------------------------------------------
# 2. Compose 파일 목록 결정 (.env는 바꾸지 않음)
# -------------------------------------------------------------------

# 기존 구성: .env의 COMPOSE_FILE (dev는 docker-compose.dev.yaml 포함), 없으면 기본 파일
DIRECT_COMPOSE_FILE="$(env_get COMPOSE_FILE)"
DIRECT_COMPOSE_FILE="${DIRECT_COMPOSE_FILE:-docker-compose.yaml}"

# ProxySQL 구성: 기존 목록 + docker-compose.proxysql.yaml
if [[ ":${DIRECT_COMPOSE_FILE}:" == *":${PROXYSQL_COMPOSE}:"* ]]; then
  PROXY_COMPOSE_FILE="$DIRECT_COMPOSE_FILE"
  DIRECT_COMPOSE_FILE="$(
    printf '%s' "$DIRECT_COMPOSE_FILE" \
      | tr ':' '\n' \
      | grep -vxF "$PROXYSQL_COMPOSE" \
      | paste -sd: -
  )"
else
  PROXY_COMPOSE_FILE="${DIRECT_COMPOSE_FILE}:${PROXYSQL_COMPOSE}"
fi

# 이 스크립트의 docker compose 명령은 기본적으로 ProxySQL 구성을 사용한다.
export COMPOSE_FILE="$PROXY_COMPOSE_FILE"
export PROXYSQL_CNF_PATH

log "ProxySQL 구성: COMPOSE_FILE=${PROXY_COMPOSE_FILE}"
log "되돌릴 구성:   COMPOSE_FILE=${DIRECT_COMPOSE_FILE}"

# -------------------------------------------------------------------
# 3. 동시 배포 차단 및 런타임 설정 준비 (deploy.sh와 같은 잠금 사용)
# -------------------------------------------------------------------

exec 9>"$LOCK_FILE"

log "배포 잠금 대기 (최대 ${LOCK_WAIT}초)"

flock -w "$LOCK_WAIT" 9 || {
  log "다른 배포가 진행 중입니다."
  exit 75
}

log "Parameter Store 런타임 설정 조회"
load_runtime_parameters

[[ -n "${DB_USERNAME:-}" && -n "${DB_PASSWORD:-}" ]] \
  || fail_config "DB_USERNAME 또는 DB_PASSWORD가 비어 있습니다."

log "Compose 설정 확인"
docker compose config --quiet

ECR_REGISTRY="$(env_get ECR_REGISTRY)"
ECR_REPOSITORY_PREFIX="$(env_get ECR_REPOSITORY_PREFIX)"
ECR_REPOSITORY_PREFIX="${ECR_REPOSITORY_PREFIX:-lookddak}"
PREV_TAG="$(env_get "$TAG_VAR")"

[[ -n "$ECR_REGISTRY" ]] \
  || fail_config ".env의 ECR_REGISTRY 값이 비어 있습니다."

[[ "$ECR_REPOSITORY_PREFIX" =~ ^[a-z0-9-]+$ ]] \
  || fail_config "ECR_REPOSITORY_PREFIX 값이 올바르지 않습니다: '$ECR_REPOSITORY_PREFIX'"

readonly IMAGE="${ECR_REGISTRY}/${ECR_REPOSITORY_PREFIX}-spring"

log "Spring 현재 태그=${PREV_TAG:-없음}, 요청 태그=${NEW_TAG}"

# -------------------------------------------------------------------
# 4. 이미지 확보 (실패해도 실행 중인 컨테이너는 바뀌지 않음)
# -------------------------------------------------------------------

log "EC2 인스턴스 역할로 ECR 로그인"

aws ecr get-login-password --region "$AWS_REGION" \
  | docker login --username AWS --password-stdin "$ECR_REGISTRY" >/dev/null \
  || { record "ecr-login-failed-service-unchanged"; log "ECR 로그인 실패"; exit 1; }

log "Spring 이미지 pull: ${IMAGE}:${NEW_TAG}"
docker pull "${IMAGE}:${NEW_TAG}" \
  || { record "image-pull-failed-service-unchanged"; log "Spring 이미지 pull 실패"; exit 1; }

log "ProxySQL 이미지 pull"
docker compose pull proxysql \
  || { record "proxysql-pull-failed-service-unchanged"; log "ProxySQL 이미지 pull 실패"; exit 1; }

# -------------------------------------------------------------------
# 5. ProxySQL 기동 및 사전 확인 (Spring은 아직 기존 연결 그대로)
# -------------------------------------------------------------------

log "ProxySQL 기동"

if ! docker compose up -d --no-deps proxysql \
  || ! wait_for_proxysql \
  || ! check_proxysql_login; then
  record "proxysql-check-failed-spring-unchanged"
  log "ProxySQL 확인 실패. Spring은 변경하지 않았습니다."
  exit 1
fi

# -------------------------------------------------------------------
# 6. Spring을 ProxySQL 경유로 재생성
# -------------------------------------------------------------------

if recreate_spring "$PROXY_COMPOSE_FILE" "$NEW_TAG"; then
  record "success"
  log "완료: Spring(${NEW_TAG})이 ProxySQL을 거쳐 RDS에 접속합니다."

  if [[ ":$(env_get COMPOSE_FILE):" != *":${PROXYSQL_COMPOSE}:"* ]]; then
    log "주의: .env의 COMPOSE_FILE에 ${PROXYSQL_COMPOSE}가 없습니다."
    log "      이대로 deploy.sh be를 실행하면 Spring이 RDS 직접 연결로 다시 만들어집니다."
    log "      ProxySQL 경유를 유지하려면 .env를 COMPOSE_FILE=${PROXY_COMPOSE_FILE} 로 바꾸세요."
  fi

  exit 0
fi

# -------------------------------------------------------------------
# 7. 실패: Spring을 이전 태그 + RDS 직접 연결로 복구
# -------------------------------------------------------------------

log "Spring 기동 실패. 최근 로그:"
docker compose logs --tail 50 spring || true

if [[ -z "$PREV_TAG" ]]; then
  record "failed-no-previous"
  log "되돌아갈 이전 태그가 없습니다. 즉시 수동 확인이 필요합니다."
  exit 2
fi

log "이전 태그(${PREV_TAG}) + RDS 직접 연결로 복구"

if recreate_spring "$DIRECT_COMPOSE_FILE" "$PREV_TAG"; then
  record "rolled-back-direct"
  log "복구 성공: Spring(${PREV_TAG})이 RDS에 직접 접속합니다. ProxySQL은 원인 확인을 위해 남겨 두었습니다."
  exit 1
fi

record "rollback-failed"
log "복구까지 실패했습니다. 즉시 수동 확인이 필요합니다."
exit 2
