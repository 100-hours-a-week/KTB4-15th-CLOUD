#!/usr/bin/env bash
# V1 MySQL 마이그레이션 스크립트 공통 함수 (verify-sync.sh, cutover.sh에서 source)
# - mysql 클라이언트는 EC2에 설치하지 않고 mysql:8.4 임시 컨테이너(--network host)를 하나 띄워 재사용한다.
#   (매 쿼리마다 docker run을 하면 컨테이너 기동 시간이 전환 대기 시간에 더해지므로 docker exec로 재사용)
# - 비밀번호는 명령 인자에 넣지 않고 MYSQL_PWD 환경 변수로만 전달한다.

readonly AWS_REGION="${AWS_REGION:-ap-northeast-2}"
readonly MYSQL_CLIENT_IMAGE="${MYSQL_CLIENT_IMAGE:-mysql:8.4}"
readonly PROXYSQL_ADMIN_HOST="127.0.0.1"
readonly PROXYSQL_ADMIN_PORT="6032"
readonly PROXYSQL_ADMIN_USER="radmin"
# shellcheck disable=SC2034  # verify-sync.sh, cutover.sh에서 사용
readonly WRITER_HOSTGROUP="10"

CLI_CONTAINER="mig-mysql-cli-$$"

ts() {
  date '+%F %T.%3N'
}

log() {
  echo "[$(ts)] $*"
}

die() {
  log "ERROR: $*"
  exit 1
}

get_parameter() {
  aws ssm get-parameter \
    --region "$AWS_REGION" \
    --name "$1" \
    --with-decryption \
    --query Parameter.Value \
    --output text
}

# 환경(dev, prod)별 접속 정보 로드
load_credentials() {
  local env_name="$1"

  RDS_ADMIN="$(get_parameter "/lookddak/${env_name}/rds/admin/username")"
  RDS_ADMIN_PW="$(get_parameter "/lookddak/${env_name}/rds/admin/password")"
  # shellcheck disable=SC2034  # verify-sync.sh에서 사용
  RDS_DATABASE="$(get_parameter "/lookddak/${env_name}/rds/database")"
  PROXYSQL_ADMIN_PW="$(get_parameter "/lookddak/${env_name}/proxysql/admin/password")"

  [[ -n "$RDS_ADMIN" && -n "$RDS_ADMIN_PW" && -n "$PROXYSQL_ADMIN_PW" ]] \
    || die "Parameter Store 값을 읽지 못했습니다 (${env_name})"
}

start_cli() {
  docker run -d --rm \
    --name "$CLI_CONTAINER" \
    --network host \
    --entrypoint sleep \
    "$MYSQL_CLIENT_IMAGE" infinity >/dev/null \
    || die "mysql 클라이언트 컨테이너를 띄우지 못했습니다"
}

stop_cli() {
  docker rm -f "$CLI_CONTAINER" >/dev/null 2>&1 || true
}

# SQL은 명령 인자(-e)가 아니라 stdin으로 넘긴다. (repl 비밀번호가 들어가는 SQL이 ps에 보이지 않게)

# RDS 쿼리: q_db <host> <sql>  (탭 구분, 헤더 없음)
q_db() {
  local host="$1"
  shift
  printf '%s\n' "$*" | MYSQL_PWD="$RDS_ADMIN_PW" docker exec -i -e MYSQL_PWD "$CLI_CONTAINER" \
    mysql -h "$host" -u "$RDS_ADMIN" --ssl-mode=REQUIRED --connect-timeout=5 -N -B
}

# RDS 쿼리, 사람이 읽는 형식: q_db_v <host> <sql>
q_db_v() {
  local host="$1"
  shift
  printf '%s\n' "$*" | MYSQL_PWD="$RDS_ADMIN_PW" docker exec -i -e MYSQL_PWD "$CLI_CONTAINER" \
    mysql -h "$host" -u "$RDS_ADMIN" --ssl-mode=REQUIRED --connect-timeout=5 -t
}

# ProxySQL admin 쿼리: q_admin <sql>
q_admin() {
  printf '%s\n' "$*" | MYSQL_PWD="$PROXYSQL_ADMIN_PW" docker exec -i -e MYSQL_PWD "$CLI_CONTAINER" \
    mysql -h "$PROXYSQL_ADMIN_HOST" -P "$PROXYSQL_ADMIN_PORT" -u "$PROXYSQL_ADMIN_USER" \
    --connect-timeout=5 -N -B
}

q_admin_v() {
  printf '%s\n' "$*" | MYSQL_PWD="$PROXYSQL_ADMIN_PW" docker exec -i -e MYSQL_PWD "$CLI_CONTAINER" \
    mysql -h "$PROXYSQL_ADMIN_HOST" -P "$PROXYSQL_ADMIN_PORT" -u "$PROXYSQL_ADMIN_USER" \
    --connect-timeout=5 -t
}

# SHOW REPLICA STATUS에서 필드 하나 읽기: replica_field <host> <field>
replica_field() {
  printf '%s\n' 'SHOW REPLICA STATUS\G' | MYSQL_PWD="$RDS_ADMIN_PW" docker exec -i -e MYSQL_PWD "$CLI_CONTAINER" \
    mysql -h "$1" -u "$RDS_ADMIN" --ssl-mode=REQUIRED --connect-timeout=5 \
    | awk -F': ' -v k="$2" '{gsub(/^ +/, "", $1)} $1 == k {print $2; exit}'
}

# SHOW BINARY LOG STATUS → "file<TAB>position"
binlog_position() {
  q_db "$1" "SHOW BINARY LOG STATUS" | awk -F'\t' 'NR == 1 {print $1 "\t" $2}'
}
