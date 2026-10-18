#!/usr/bin/env bash
# V1 Prod FastAPI의 PostgreSQL 연결을 기존 EC2 DB 직결에서 PgBouncer 경유로 전환한다.
# PostgreSQL은 재시작하지 않으며, 실패하면 .env와 FastAPI를 기존 직결 상태로 복구한다.
set -Eeuo pipefail
set +x

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common-functions.sh
source "${ROOT}/common-functions.sh"

RUN_ID="${1:-}"
POSTGRES_BIND_IP="${POSTGRES_BIND_IP:-}"
ENV_FILE="${APP_DIR}/.env"
PARAMETER_LOADER="${APP_DIR}/scripts/load-parameters.sh"

require_root
require_run_id "$RUN_ID"
require_commands aws docker flock grep install mktemp sed awk seq sleep
[[ "$POSTGRES_BIND_IP" =~ ^10\.20\.[0-9]{1,3}\.[0-9]{1,3}$ ]] \
  || die "POSTGRES_BIND_IP에는 운영 VPC의 EC2 사설 IP를 지정하세요"

test -f "$ENV_FILE"
test -f "$PARAMETER_LOADER"
test -f "$COMPOSE_OVERLAY"
test -f "${PGBOUNCER_DIR}/pgbouncer.ini"
test -f "${PGBOUNCER_DIR}/userlist.txt"
assert_overlay_not_active
require_healthy lookddak-postgresql
require_healthy lookddak-fastapi
! docker inspect lookddak-pgbench >/dev/null 2>&1 \
  || die "pgbench 컨테이너가 실행 또는 생성된 상태입니다"

acquire_migration_lock
start_run_log "$RUN_ID" activate-pgbouncer

result_dir="${RESULT_ROOT}/${RUN_ID}"
env_backup="${result_dir}/env.before-pgbouncer"
install -o root -g root -m 0600 "$ENV_FILE" "$env_backup"

ROLLBACK_REQUIRED=1
rollback() {
  local exit_code=$?
  trap - EXIT INT TERM
  set +e
  if [[ "$ROLLBACK_REQUIRED" -eq 1 ]]; then
    log "ROLLBACK_STARTED=exit_code=${exit_code}"
    rm -f -- "${env_tmp:-}"
    install -o root -g root -m 0600 "$env_backup" "$ENV_FILE"
    unset FASTAPI_DATABASE_URL FASTAPI_CHECKPOINT_DSN \
      PGBOUNCER_APP_USERNAME PGBOUNCER_APP_PASSWORD
    export AWS_REGION
    # shellcheck source=/dev/null
    source "$PARAMETER_LOADER"
    load_runtime_parameters
    app_compose up -d --no-deps --force-recreate fastapi
    for _ in $(seq 1 180); do
      [[ "$(container_health lookddak-fastapi 2>/dev/null || true)" == "healthy" ]] && break
      sleep 2
    done
    log "ROLLBACK_FASTAPI_HEALTH=$(container_health lookddak-fastapi 2>/dev/null || echo missing)"
    docker stop -t 30 lookddak-pgbouncer >/dev/null 2>&1
    docker rm -f lookddak-pgbouncer >/dev/null 2>&1
    declare -F cleanup_runtime_parameters >/dev/null && cleanup_runtime_parameters
    log "ROLLBACK_FINISHED=true"
  fi
  exit "$exit_code"
}
trap rollback EXIT INT TERM

env_tmp="$(mktemp "${APP_DIR}/.env.pgbouncer.XXXXXX")"
grep -Ev '^(COMPOSE_FILE|POSTGRES_BIND_IP)=' "$ENV_FILE" > "$env_tmp"
{
  printf 'COMPOSE_FILE=docker-compose.yaml:docker-compose.postgres-migration.yaml\n'
  printf 'POSTGRES_BIND_IP=%s\n' "$POSTGRES_BIND_IP"
} >> "$env_tmp"
install -o root -g root -m 0600 "$env_tmp" "$ENV_FILE"
rm -f -- "$env_tmp"

export AWS_REGION POSTGRES_BIND_IP
# shellcheck source=/dev/null
source "$PARAMETER_LOADER"
load_runtime_parameters

app_compose up -d --no-deps pgbouncer
for _ in $(seq 1 30); do
  [[ "$(container_health lookddak-pgbouncer 2>/dev/null || true)" == "healthy" ]] && break
  sleep 2
done
require_healthy lookddak-pgbouncer
[[ "$(active_pgbouncer_backend)" == 'postgresql|5432|lookddak_ai||0' ]] \
  || die "PgBouncer가 기존 EC2 PostgreSQL을 바라보지 않습니다"

# 인증정보는 명령행 인자나 로그가 아닌 stdin으로만 전달한다.
pgbouncer_query="$({
  printf '%s\n' "$PGBOUNCER_APP_PASSWORD" \
    | docker exec -i lookddak-postgresql sh -c '
        IFS= read -r PGPASSWORD
        export PGPASSWORD
        psql -X -v ON_ERROR_STOP=1 -At \
          "host=pgbouncer port=6432 dbname=lookddak_ai user=lookddak_app connect_timeout=5" \
          -c "SELECT current_database(), current_user, inet_server_port();"
      '
})"
[[ "$pgbouncer_query" == 'lookddak_ai|lookddak_app|5432' ]] \
  || die "PgBouncer 경유 PostgreSQL 쿼리 결과가 예상과 다릅니다"
log "PGBOUNCER_QUERY=${pgbouncer_query}"

app_compose up -d --no-deps --force-recreate fastapi
for _ in $(seq 1 180); do
  [[ "$(container_health lookddak-fastapi 2>/dev/null || true)" == "healthy" ]] && break
  sleep 2
done
require_healthy lookddak-fastapi

docker exec lookddak-fastapi python -c '
import os
from urllib.parse import urlparse
url = urlparse(os.environ["DATABASE_URL"])
assert (url.hostname, url.port, url.username, url.path) == (
    "pgbouncer", 6432, "lookddak_app", "/lookddak_ai"
)
print("FASTAPI_DATABASE_TARGET=pgbouncer:6432/lookddak_ai")
'
docker exec lookddak-fastapi python -c '
import os
from urllib.parse import parse_qs, urlparse
url = urlparse(os.environ["CHECKPOINT_DSN"])
assert parse_qs(url.query).get("options") == ["-csearch_path=langgraph"]
print("FASTAPI_CHECKPOINT_SCHEMA=langgraph")
'

require_healthy lookddak-postgresql
! docker inspect lookddak-pgbench >/dev/null 2>&1 \
  || die "pgbench 컨테이너가 의도치 않게 생성됐습니다"

ROLLBACK_REQUIRED=0
cleanup_runtime_parameters
trap - EXIT INT TERM
log "ACTIVATE_PGBOUNCER_SUCCEEDED=true"
log "POSTGRESQL_RESTARTED=false"
log "PGBENCH_STARTED=false"
