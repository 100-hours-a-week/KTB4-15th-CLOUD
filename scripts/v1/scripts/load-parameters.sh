#!/usr/bin/env bash
# EC2 배치 경로: /opt/lookddak/scripts/load-parameters.sh
#
# 직접 실행하는 파일이 아니라 bootstrap.sh와 deploy.sh에서 source한다.
# Parameter Store 조회, 연결 문자열 조합, export, cleanup 함수만 제공한다.

get_parameter() {
  local parameter_name="$1"
  local value

  if ! value="$(
    aws ssm get-parameter \
      --region "$AWS_REGION" \
      --name "$parameter_name" \
      --with-decryption \
      --query "Parameter.Value" \
      --output text
  )"; then
    echo "Parameter Store 조회 실패: ${parameter_name}" >&2
    return 1
  fi

  if [[ -z "$value" || "$value" == "None" ]]; then
    echo "Parameter Store 값이 비어 있습니다: ${parameter_name}" >&2
    return 1
  fi

  printf '%s' "$value"
}

urlencode() {
  VALUE="$1" python3 -c \
    'import os, urllib.parse; print(urllib.parse.quote(os.environ["VALUE"], safe=""))'
}

load_runtime_parameters() {
  local postgres_user_encoded
  local postgres_password_encoded
  local postgres_db_encoded

  POSTGRES_DB="$(
    get_parameter "/lookddak/prod/postgresql/database"
  )"

  POSTGRES_USER="$(
    get_parameter "/lookddak/prod/postgresql/username"
  )"

  POSTGRES_PASSWORD="$(
    get_parameter "/lookddak/prod/postgresql/password"
  )"

  RDS_HOST="$(
    get_parameter "/lookddak/prod/rds/host"
  )"

  RDS_PORT="$(
    get_parameter "/lookddak/prod/rds/port"
  )"

  RDS_DATABASE="$(
    get_parameter "/lookddak/prod/rds/database"
  )"

  RDS_APP_USERNAME="$(
    get_parameter "/lookddak/prod/rds/app/username"
  )"

  RDS_APP_PASSWORD="$(
    get_parameter "/lookddak/prod/rds/app/password"
  )"

  JWT_SECRET="$(
    get_parameter "/lookddak/prod/spring/jwt-secret"
  )"

  SENTRY_DSN="$(
    get_parameter "/lookddak/prod/spring/sentry_dsn"
  )"

  RUNWARE_VTON_API_KEY="$(
    get_parameter "/lookddak/prod/fastapi/runware-vton-api-key"
  )"

  RUNWARE_LLM_API_KEY="$(
    get_parameter "/lookddak/prod/fastapi/runware-llm-api-key"
  )"

  OPENAI_API_KEY="$(
    get_parameter "/lookddak/prod/fastapi/openAI-api-key"
  )"

  INTERNAL_API_KEY="$(
    get_parameter "/lookddak/prod/internal/ai-api-key"
  )"

  AI_INTERNAL_API_KEY="$INTERNAL_API_KEY"

  postgres_user_encoded="$(urlencode "$POSTGRES_USER")"
  postgres_password_encoded="$(urlencode "$POSTGRES_PASSWORD")"
  postgres_db_encoded="$(urlencode "$POSTGRES_DB")"

  DATABASE_URL="postgresql://${postgres_user_encoded}:${postgres_password_encoded}@postgresql:5432/${postgres_db_encoded}"
  CHECKPOINT_DSN="${DATABASE_URL}?options=-csearch_path%3Dlanggraph"

  DB_URL="jdbc:mysql://${RDS_HOST}:${RDS_PORT}/${RDS_DATABASE}?sslMode=REQUIRED&serverTimezone=UTC&characterEncoding=UTF-8"
  DB_USERNAME="$RDS_APP_USERNAME"
  DB_PASSWORD="$RDS_APP_PASSWORD"

  export \
    POSTGRES_DB \
    POSTGRES_USER \
    POSTGRES_PASSWORD \
    DATABASE_URL \
    CHECKPOINT_DSN \
    DB_URL \
    DB_USERNAME \
    DB_PASSWORD \
    JWT_SECRET \
    SENTRY_DSN \
    RUNWARE_VTON_API_KEY \
    RUNWARE_LLM_API_KEY \
    OPENAI_API_KEY \
    INTERNAL_API_KEY \
    AI_INTERNAL_API_KEY
}

cleanup_runtime_parameters() {
  unset \
    POSTGRES_DB \
    POSTGRES_USER \
    POSTGRES_PASSWORD \
    DATABASE_URL \
    CHECKPOINT_DSN \
    RDS_HOST \
    RDS_PORT \
    RDS_DATABASE \
    RDS_APP_USERNAME \
    RDS_APP_PASSWORD \
    DB_URL \
    DB_USERNAME \
    DB_PASSWORD \
    JWT_SECRET \
    SENTRY_DSN \
    RUNWARE_VTON_API_KEY \
    RUNWARE_LLM_API_KEY \
    OPENAI_API_KEY \
    INTERNAL_API_KEY \
    AI_INTERNAL_API_KEY
}
