#!/usr/bin/env bash
# EC2 배치 경로: /opt/lookddak/scripts/bootstrap.sh
# 실행: sudo /opt/lookddak/scripts/bootstrap.sh
#
# 역할: 최초 전체 스택 기동 또는 EC2 전체 스택 복구
#
# 기동 순서: PostgreSQL → langgraph → FastAPI → Spring → Next.js → Nginx

set -Eeuo pipefail

readonly APP_DIR="/opt/lookddak"
readonly ENV_FILE="${APP_DIR}/.env"
readonly COMPOSE_FILE="${APP_DIR}/docker-compose.yaml"
readonly PARAMETER_LOADER="${APP_DIR}/scripts/load-parameters.sh"
readonly LOCK_FILE="/var/lock/lookddak-deploy.lock"
readonly AWS_REGION="ap-northeast-2"

readonly LOCK_WAIT=60
readonly WAIT_TIMEOUT=300
readonly CHECK_INTERVAL=5

log() {
  echo "[$(date '+%F %T')] [bootstrap] $*"
}

fail() {
  log "$1"
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 \
    || fail "필수 명령이 없습니다: $1"
}

# .env에서 비민감 설정값을 읽는다.
env_get() {
  local key="$1"

  grep -E "^${key}=" "$ENV_FILE" \
    | tail -n 1 \
    | cut -d= -f2- || true
}

# 컨테이너가 실제 running 상태인지 확인한다.
container_running() {
  local service="$1"
  local container_id

  container_id="$(docker compose ps -q "$service")"
  [[ -n "$container_id" ]] || return 1

  [[ "$(
    docker inspect \
      --format '{{.State.Running}}' \
      "$container_id" 2>/dev/null
  )" == "true" ]]
}

# 1차 테스트용 검사:
# HTTP 응답 대신 컨테이너 내부에서 서비스 포트가 열렸는지만 확인한다.
service_port_ready() {
  local service="$1"

  container_running "$service" || return 1

  case "$service" in
    postgresql)
      docker compose exec -T postgresql \
        pg_isready \
          -U "$POSTGRES_USER" \
          -d "$POSTGRES_DB" \
        >/dev/null 2>&1
      ;;

    fastapi)
      docker compose exec -T fastapi \
        python -c \
        'import socket; socket.create_connection(("127.0.0.1", 8000), 3).close()' \
        >/dev/null 2>&1
      ;;

    spring)
      docker compose exec -T spring \
        bash -c \
        'exec 3<>/dev/tcp/127.0.0.1/8080' \
        >/dev/null 2>&1
      ;;

    nextjs)
      docker compose exec -T nextjs \
        node -e '
          const net = require("net");
          const socket = net.createConnection({
            host: "127.0.0.1",
            port: 3000
          });

          socket.setTimeout(3000);

          socket.on("connect", () => {
            socket.end();
            process.exit(0);
          });

          socket.on("timeout", () => process.exit(1));
          socket.on("error", () => process.exit(1));
        ' >/dev/null 2>&1
      ;;

    *)
      return 1
      ;;
  esac
}

# 지정 서비스가 running 상태가 되고 포트를 열 때까지 기다린다.
wait_for_service() {
  local service="$1"
  local deadline=$((SECONDS + WAIT_TIMEOUT))

  log "${service} 컨테이너와 포트 준비 대기"

  while ((SECONDS < deadline)); do
    if service_port_ready "$service"; then
      log "${service} 실행 및 포트 확인 성공"
      return 0
    fi

    sleep "$CHECK_INTERVAL"
  done

  log "${service}가 ${WAIT_TIMEOUT}초 안에 준비되지 않았습니다."
  docker compose ps "$service" || true
  return 1
}

# 서비스 하나를 실행하고 포트가 준비될 때까지 기다린다.
start_service() {
  local service="$1"

  log "${service} 컨테이너 실행"

  docker compose up \
    -d \
    --no-deps \
    "$service"

  wait_for_service "$service"
}

# 실패 시 상태만 남긴다.
# 애플리케이션 로그와 오류 원인은 CloudWatch Logs에서 확인한다.
on_error() {
  local exit_code=$?

  trap - ERR
  set +e

  log "최초 기동 실패"
  docker compose ps || true
  log "상세 로그는 서비스별 CloudWatch Logs에서 확인하세요."

  exit "$exit_code"
}

# -------------------------------------------------------------------
# 1. 실행 환경과 필수 파일 확인
# -------------------------------------------------------------------

for command_name in aws docker flock grep cut python3; do
  require_command "$command_name"
done

[[ "$EUID" -eq 0 ]] \
  || fail "bootstrap.sh는 root 권한으로 실행해야 합니다."

[[ -d "$APP_DIR" ]] \
  || fail "애플리케이션 디렉터리가 없습니다: $APP_DIR"

[[ -f "$ENV_FILE" ]] \
  || fail "환경 파일이 없습니다: $ENV_FILE"

[[ -f "$COMPOSE_FILE" ]] \
  || fail "docker-compose.yaml이 없습니다."

[[ -f "$PARAMETER_LOADER" ]] \
  || fail "load-parameters.sh가 없습니다."

# -------------------------------------------------------------------
# 2. 공통 Parameter Store 함수와 종료 처리 등록
# -------------------------------------------------------------------

# source해야 load-parameters.sh가 export한 값이
# 현재 bootstrap.sh 셸과 docker compose에 전달된다.
source "$PARAMETER_LOADER"

# 스크립트 종료 시 현재 셸에서 런타임 시크릿을 제거한다.
trap cleanup_runtime_parameters EXIT
trap on_error ERR

cd "$APP_DIR"

# -------------------------------------------------------------------
# 3. 다른 bootstrap 또는 deploy.sh와 동시 실행 차단
# -------------------------------------------------------------------

exec 9>"$LOCK_FILE"

log "배포 잠금 대기 (최대 ${LOCK_WAIT}초)"

if ! flock -w "$LOCK_WAIT" 9; then
  fail "다른 배포가 진행 중입니다."
fi

# -------------------------------------------------------------------
# 4. Parameter Store 조회 및 Compose 설정 확인
# -------------------------------------------------------------------

log "Parameter Store 런타임 설정 조회"
load_runtime_parameters
log "Parameter Store 런타임 설정 조회 성공"

# 실제 값은 출력하지 않고 Compose 해석 가능 여부만 확인한다.
log "Compose 설정 확인"
docker compose config --quiet

# -------------------------------------------------------------------
# 5. ECR 로그인 및 전체 이미지 pull
# -------------------------------------------------------------------

ECR_REGISTRY="$(env_get ECR_REGISTRY)"

[[ -n "$ECR_REGISTRY" ]] \
  || fail ".env의 ECR_REGISTRY 값이 비어 있습니다."

log "EC2 인스턴스 역할로 ECR 로그인"

aws ecr get-login-password \
  --region "$AWS_REGION" \
  | docker login \
      --username AWS \
      --password-stdin "$ECR_REGISTRY" \
      >/dev/null

log "전체 이미지 pull"

docker compose pull \
  postgresql \
  fastapi \
  spring \
  nextjs \
  nginx

# -------------------------------------------------------------------
# 6. PostgreSQL 선기동
# -------------------------------------------------------------------

start_service postgresql

# -------------------------------------------------------------------
# 7. FastAPI가 사용할 langgraph 스키마 준비
# -------------------------------------------------------------------

log "PostgreSQL langgraph 스키마 준비"

docker compose exec -T postgresql sh -c '
  PGPASSWORD="$POSTGRES_PASSWORD" \
  psql \
    --host=127.0.0.1 \
    --username="$POSTGRES_USER" \
    --dbname="$POSTGRES_DB" \
    --set ON_ERROR_STOP=1 \
    --command="CREATE SCHEMA IF NOT EXISTS langgraph;"
'

log "langgraph 스키마 준비 완료"

# -------------------------------------------------------------------
# 8. 애플리케이션을 의존 순서대로 기동
# -------------------------------------------------------------------

start_service fastapi
start_service spring
start_service nextjs

# -------------------------------------------------------------------
# 9. Nginx 기동 및 설정 검사
# -------------------------------------------------------------------

log "Nginx 실행"

docker compose up \
  -d \
  --no-deps \
  nginx

if ! container_running nginx; then
  fail "Nginx 컨테이너가 실행되지 않았습니다."
fi

# 외부 HTTPS 요청은 아직 검사하지 않고 Nginx 설정 문법만 확인한다.
docker compose exec -T nginx nginx -t >/dev/null

log "Nginx 실행 및 설정 확인 성공"

# -------------------------------------------------------------------
# 10. 최종 상태 출력
# -------------------------------------------------------------------

docker compose ps

log "최초 전체 스택 기동 완료"
exit 0
