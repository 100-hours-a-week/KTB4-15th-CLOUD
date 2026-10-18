#!/usr/bin/env bash
# 공통 앱 계정, PgBouncer 인증 파일, EC2/RDS 대상 설정을 준비한다.
# 컨테이너를 시작하거나 기존 컨테이너를 재기동하지 않는다.
set -Eeuo pipefail
set +x

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common-functions.sh
source "${ROOT}/common-functions.sh"

MODE="${1:-check}"
[[ "$MODE" == "check" || "$MODE" == "run" ]] || die "사용법: $0 {check|run}"
require_root
require_commands aws docker flock grep install mktemp sed

test -f "${PRODUCTION_MIGRATION_ROOT}/sql/setup-ec2-app-role.sql"
test -f "${PRODUCTION_MIGRATION_ROOT}/sql/setup-ec2-migration-role.sql"
test -f "${PGBOUNCER_DIR}/pgbouncer.ec2.ini"
test -f "${PGBOUNCER_DIR}/pgbouncer.rds.ini.template"
assert_overlay_not_active
require_healthy lookddak-postgresql
load_rds_parameters
trap cleanup_secrets EXIT

[[ "$RDS_APP_USERNAME" == "lookddak_app" ]] || die "RDS 앱 계정이 lookddak_app이 아닙니다"
[[ -n "$RDS_APP_PASSWORD" ]] || die "RDS 앱 계정 비밀번호가 비어 있습니다"

if [[ "$MODE" == "check" ]]; then
  ec2_admin_sql -Atc "SELECT 'source_database=' || current_database(); SELECT 'app_role_exists=' || EXISTS(SELECT 1 FROM pg_roles WHERE rolname='lookddak_app');"
  log "CHECK_COMPLETE=run 모드는 DB 계정과 런타임 파일을 준비하며 컨테이너는 기동하지 않습니다"
  exit 0
fi

acquire_migration_lock
install -d -o root -g root -m 0750 "$PGBOUNCER_DIR"

# 비밀번호는 docker exec 명령행이나 로그가 아니라 stdin으로만 전달한다.
docker cp "${PRODUCTION_MIGRATION_ROOT}/sql/setup-ec2-app-role.sql" lookddak-postgresql:/tmp/setup-ec2-app-role.sql
printf '%s\n' "$RDS_APP_PASSWORD" | docker exec -i lookddak-postgresql sh -c '
  IFS= read -r LOOKDDAK_APP_PASSWORD
  export LOOKDDAK_APP_PASSWORD
  psql -X -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -f /tmp/setup-ec2-app-role.sql
  rm -f /tmp/setup-ec2-app-role.sql
'

docker cp "${PRODUCTION_MIGRATION_ROOT}/sql/setup-ec2-migration-role.sql" lookddak-postgresql:/tmp/setup-ec2-migration-role.sql
printf '%s\n' "$RDS_MIGRATION_PASSWORD" | docker exec -i lookddak-postgresql sh -c '
  IFS= read -r LOOKDDAK_MIGRATION_PASSWORD
  export LOOKDDAK_MIGRATION_PASSWORD
  psql -X -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -f /tmp/setup-ec2-migration-role.sql
  rm -f /tmp/setup-ec2-migration-role.sql
'

runtime_uid="$(docker run --rm --network none --read-only --cap-drop ALL \
  --entrypoint id edoburu/pgbouncer:v1.26.0-p0@sha256:b17551c776ef7e5769ef80b956d20f85e2fd25dd8912d31d58f782aad495b711 -u)"
runtime_gid="$(docker run --rm --network none --read-only --cap-drop ALL \
  --entrypoint id edoburu/pgbouncer:v1.26.0-p0@sha256:b17551c776ef7e5769ef80b956d20f85e2fd25dd8912d31d58f782aad495b711 -g)"

auth_tmp="$(mktemp "${PGBOUNCER_DIR}/userlist.tmp.XXXXXX")"
trap 'rm -f -- "${auth_tmp:-}"; cleanup_secrets' EXIT
{
  printf '"lookddak_app" "'
  printf '%s' "$RDS_APP_PASSWORD"
  printf '"\n"pgbouncer_admin" ""\n'
} > "$auth_tmp"
install -o "$runtime_uid" -g "$runtime_gid" -m 0600 "$auth_tmp" "${PGBOUNCER_DIR}/userlist.txt"

sed \
  -e "s|__RDS_HOST__|${RDS_HOST}|g" \
  -e "s|__RDS_PORT__|${RDS_PORT}|g" \
  -e "s|__RDS_DATABASE__|${RDS_DATABASE}|g" \
  "${PGBOUNCER_DIR}/pgbouncer.rds.ini.template" \
  > "${PGBOUNCER_DIR}/pgbouncer.rds.ini"
chmod 0644 "${PGBOUNCER_DIR}/pgbouncer.rds.ini"
cp "${PGBOUNCER_DIR}/pgbouncer.ec2.ini" "${PGBOUNCER_DIR}/pgbouncer.ini"
chmod 0644 "${PGBOUNCER_DIR}/pgbouncer.ini"

grep -Fxq 'lookddak_ai = host=postgresql port=5432 dbname=lookddak_ai' "${PGBOUNCER_DIR}/pgbouncer.ini"
grep -Fxq "lookddak_ai = host=${RDS_HOST} port=${RDS_PORT} dbname=${RDS_DATABASE}" "${PGBOUNCER_DIR}/pgbouncer.rds.ini"
ec2_admin_sql -Atc "SELECT 'app_role_ready=' || (rolcanlogin AND NOT rolsuper) FROM pg_roles WHERE rolname='lookddak_app';"
ec2_admin_sql -Atc "SELECT 'migration_role_ready=' || (rolcanlogin AND rolreplication AND NOT rolsuper) FROM pg_roles WHERE rolname='lookddak_migration';"
log "PREPARE_RUNTIME_SUCCEEDED=no containers started or restarted"
