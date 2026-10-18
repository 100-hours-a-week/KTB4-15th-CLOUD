#!/usr/bin/env bash
# V1 Prod PostgreSQL 마이그레이션 스크립트 공통 함수.
# 이 파일은 직접 실행하지 않고 다른 스크립트에서 source한다.

readonly APP_DIR="${APP_DIR:-/opt/lookddak}"
readonly PRODUCTION_MIGRATION_ROOT="${PRODUCTION_MIGRATION_ROOT:-${APP_DIR}/scripts/migration/postgres/production}"
readonly RESULT_ROOT="${RESULT_ROOT:-${PRODUCTION_MIGRATION_ROOT}/results}"
readonly PGBOUNCER_DIR="${PGBOUNCER_DIR:-${APP_DIR}/pgbouncer.prod}"
readonly AWS_REGION="${AWS_REGION:-ap-northeast-2}"
readonly PARAMETER_PREFIX="${PARAMETER_PREFIX:-/lookddak/prod/v2/postgresql}"
readonly BACKUP_BUCKET="${BACKUP_BUCKET:-lookddak-prod-db-backup-686496667254-ap-northeast-2}"
readonly BACKUP_PREFIX="${BACKUP_PREFIX:-postgresql/prod}"
readonly COMPOSE_OVERLAY="${APP_DIR}/docker-compose.postgres-migration.yaml"
readonly LOCK_FILE="${LOCK_FILE:-/var/lock/lookddak-postgresql-migration.lock}"

readonly FORWARD_PUBLICATION="lookddak_prod_pg_forward_pub"
readonly ROLLBACK_PUBLICATION="lookddak_prod_pg_rollback_pub"
readonly FORWARD_SUBSCRIPTION="lookddak_prod_pg_forward_sub"
readonly ROLLBACK_SUBSCRIPTION="lookddak_prod_pg_rollback_sub"
readonly FORWARD_SLOT="lookddak_prod_pg_forward_slot"
readonly ROLLBACK_SLOT="lookddak_prod_pg_rollback_slot"

log() {
  printf '[%s] %s\n' "$(date '+%F %T%z')" "$*"
}

die() {
  log "STOP=$*" >&2
  return 1
}

require_root() {
  [[ "$EUID" -eq 0 ]] || die "root 권한으로 실행하세요"
}

require_commands() {
  local command_name
  for command_name in "$@"; do
    command -v "$command_name" >/dev/null 2>&1 \
      || die "필수 명령이 없습니다: $command_name"
  done
}

require_run_id() {
  local run_id="$1"
  [[ "$run_id" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{2,63}$ ]] \
    || die "작업 ID는 영문자·숫자로 시작하는 3~64자 영문자·숫자·점·밑줄·하이픈만 허용합니다"
}

start_run_log() {
  local run_id="$1"
  local action="$2"
  local result_dir="${RESULT_ROOT}/${run_id}"

  install -d -o root -g root -m 0750 "$result_dir"
  RUN_LOG="${result_dir}/${action}-$(date -u +%Y%m%dT%H%M%SZ).log"
  export RUN_LOG
  exec > >(tee -a "$RUN_LOG") 2>&1
}

acquire_migration_lock() {
  exec 9>"$LOCK_FILE"
  flock -n 9 || die "다른 PostgreSQL 마이그레이션 작업이 실행 중입니다"
}

get_parameter() {
  local name="$1"
  local decrypt="${2:-false}"
  local -a args

  args=(ssm get-parameter --region "$AWS_REGION" --name "$name" --query Parameter.Value --output text)
  [[ "$decrypt" == "true" ]] && args+=(--with-decryption)
  aws "${args[@]}"
}

load_rds_parameters() {
  RDS_HOST="$(get_parameter "${PARAMETER_PREFIX}/host")"
  RDS_PORT="$(get_parameter "${PARAMETER_PREFIX}/port")"
  RDS_DATABASE="$(get_parameter "${PARAMETER_PREFIX}/database")"
  RDS_ADMIN_USERNAME="$(get_parameter "${PARAMETER_PREFIX}/admin/username")"
  RDS_ADMIN_PASSWORD="$(get_parameter "${PARAMETER_PREFIX}/admin/password" true)"
  RDS_APP_USERNAME="$(get_parameter "${PARAMETER_PREFIX}/app/username")"
  RDS_APP_PASSWORD="$(get_parameter "${PARAMETER_PREFIX}/app/password" true)"
  RDS_MIGRATION_USERNAME="$(get_parameter "${PARAMETER_PREFIX}/migration/username")"
  RDS_MIGRATION_PASSWORD="$(get_parameter "${PARAMETER_PREFIX}/migration/password" true)"

  [[ "$RDS_PORT" =~ ^[0-9]+$ ]] || die "RDS port 값이 올바르지 않습니다"
  [[ "$RDS_DATABASE" == "lookddak" ]] || die "예상하지 못한 RDS 데이터베이스입니다"
  [[ "$RDS_APP_USERNAME" == "lookddak_app" ]] || die "예상하지 못한 RDS 앱 계정입니다"
  [[ "$RDS_MIGRATION_USERNAME" == "lookddak_migration" ]] || die "예상하지 못한 RDS 복제 계정입니다"
}

cleanup_secrets() {
  unset RDS_ADMIN_PASSWORD RDS_APP_PASSWORD RDS_MIGRATION_PASSWORD \
    EC2_MIGRATION_PASSWORD PGPASSWORD
}

ec2_admin_sql() {
  docker exec -i lookddak-postgresql sh -c \
    'exec psql -X -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" "$@"' \
    sh "$@"
}

rds_admin_sql() {
  [[ -n "${RDS_ADMIN_PASSWORD:-}" ]] || die "RDS 관리자 인증정보가 로드되지 않았습니다"
  docker exec -i -e PGPASSWORD="$RDS_ADMIN_PASSWORD" lookddak-pgbench \
    psql -X -v ON_ERROR_STOP=1 \
    "host=${RDS_HOST} port=${RDS_PORT} dbname=${RDS_DATABASE} user=${RDS_ADMIN_USERNAME} sslmode=require connect_timeout=5" \
    "$@"
}

pgbouncer_admin() {
  docker exec lookddak-pgbouncer psql -X -v ON_ERROR_STOP=1 \
    -h /var/run/pgbouncer -p 6432 -U pgbouncer_admin -d pgbouncer -c "$1"
}

container_health() {
  docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$1"
}

require_healthy() {
  local container="$1"
  local status
  status="$(container_health "$container" 2>/dev/null || true)"
  [[ "$status" == "healthy" ]] || die "$container 상태가 healthy가 아닙니다: ${status:-missing}"
}

app_compose() {
  (
    cd "$APP_DIR"
    docker compose "$@"
  )
}

active_pgbouncer_backend() {
  pgbouncer_admin 'SHOW DATABASES;' \
    | awk -F'|' '$1 ~ /lookddak_ai/ {for(i=1;i<=NF;i++)gsub(/^ +| +$/, "", $i); print $2 "|" $3 "|" $4 "|" $5 "|" $16}'
}

assert_overlay_not_active() {
  if grep -Eq '^COMPOSE_FILE=.*docker-compose\.postgres-migration\.yaml([:]|$)' "${APP_DIR}/.env"; then
    die "운영 마이그레이션 overlay가 이미 활성화되어 있습니다"
  fi
}
