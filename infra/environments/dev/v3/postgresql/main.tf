data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

data "aws_region" "current" {}

data "aws_kms_alias" "ssm" {
  name = "alias/aws/ssm"
}

locals {
  database_name      = "lookddak_v3"
  app_username       = "lookddak_v3_app"
  migration_username = "lookddak_v3_migration"

  parameter_names = {
    host               = "/lookddak/dev/v3/postgresql/host"
    port               = "/lookddak/dev/v3/postgresql/port"
    database           = "/lookddak/dev/v3/postgresql/database"
    app_username       = "/lookddak/dev/v3/postgresql/app/username"
    app_password       = "/lookddak/dev/v3/postgresql/app/password"
    app_database_url   = "/lookddak/dev/v3/postgresql/app/database-url"
    app_checkpoint_dsn = "/lookddak/dev/v3/postgresql/app/checkpoint-dsn"
    migration_username = "/lookddak/dev/v3/postgresql/migration/username"
    migration_password = "/lookddak/dev/v3/postgresql/migration/password"
  }

  string_parameters = {
    host = {
      name        = local.parameter_names.host
      description = "LookDDak Dev V3 PostgreSQL shared RDS endpoint"
      value       = var.postgresql_endpoint
      credential  = "connection"
    }
    port = {
      name        = local.parameter_names.port
      description = "LookDDak Dev V3 PostgreSQL shared RDS port"
      value       = tostring(var.postgresql_port)
      credential  = "connection"
    }
    database = {
      name        = local.parameter_names.database
      description = "LookDDak Dev V3 PostgreSQL isolated database name"
      value       = local.database_name
      credential  = "connection"
    }
    app_username = {
      name        = local.parameter_names.app_username
      description = "LookDDak Dev V3 PostgreSQL application username"
      value       = local.app_username
      credential  = "app"
    }
    migration_username = {
      name        = local.parameter_names.migration_username
      description = "LookDDak Dev V3 PostgreSQL migration username"
      value       = local.migration_username
      credential  = "migration"
    }
  }

  secure_parameter_names = [
    local.parameter_names.app_password,
    local.parameter_names.app_database_url,
    local.parameter_names.app_checkpoint_dsn,
    local.parameter_names.migration_password,
  ]

  parameter_arn_prefix = "arn:${data.aws_partition.current.partition}:ssm:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:parameter"

  common_tags = {
    Component   = "postgresql"
    Environment = "dev"
    Version     = "v3"
  }
}

# 비밀 값이 아닌 RDS 연결 메타데이터와 사용자명만 Terraform state로 관리한다.
# 비밀번호와 비밀번호가 포함된 DSN은 Bootstrap Runbook이 SecureString으로 생성한다.
resource "aws_ssm_parameter" "connection" {
  for_each = local.string_parameters

  name        = each.value.name
  description = each.value.description
  type        = "String"
  value       = each.value.value
  tier        = "Standard"
  data_type   = "text"

  tags = merge(local.common_tags, {
    CredentialType = each.value.credential
  })
}

# DB Access Node는 V3 Database 초기화에 필요한 V2 관리자 Parameter만 읽고,
# V3 전용 SecureString 네 개만 생성·갱신할 수 있다.
data "aws_iam_policy_document" "bootstrap_parameters" {
  statement {
    sid     = "ReadPostgresqlBootstrapParameters"
    actions = ["ssm:GetParameter"]
    resources = concat([
      "${local.parameter_arn_prefix}/lookddak/dev/v2/postgresql/admin/username",
      "${local.parameter_arn_prefix}/lookddak/dev/v2/postgresql/admin/password",
    ], [for name in local.secure_parameter_names : "${local.parameter_arn_prefix}${name}"])
  }

  statement {
    sid = "WriteV3PostgresqlSecureParameters"
    actions = [
      "ssm:AddTagsToResource",
      "ssm:PutParameter",
    ]
    resources = [for name in local.secure_parameter_names : "${local.parameter_arn_prefix}${name}"]
  }

  statement {
    sid = "UseSsmManagedKey"
    actions = [
      "kms:Decrypt",
      "kms:Encrypt",
      "kms:GenerateDataKey",
    ]
    resources = [data.aws_kms_alias.ssm.target_key_arn]

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["ssm.${data.aws_region.current.region}.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "bootstrap_parameters" {
  name   = "lookddak-dev-v3-postgresql-bootstrap-parameters"
  role   = var.db_access_instance_role_name
  policy = data.aws_iam_policy_document.bootstrap_parameters.json
}

# Terraform AWS Provider는 RDS 내부 Database·Role을 직접 관리하지 않는다.
# Private DB Access Node에서 psql을 실행하는 멱등 SSM Runbook으로 구성한다.
resource "aws_ssm_document" "bootstrap" {
  name            = "lookddak-dev-v3-postgresql-bootstrap"
  document_type   = "Command"
  document_format = "JSON"

  content = jsonencode({
    schemaVersion = "2.2"
    description   = "Create the isolated LookDdak Dev V3 PostgreSQL database and roles"
    mainSteps = [{
      action = "aws:runShellScript"
      name   = "bootstrapV3Postgresql"
      inputs = {
        timeoutSeconds = "900"
        runCommand = [<<-SHELL
          #!/bin/bash
          set -euo pipefail
          set +x
          umask 077

          readonly aws_region="${data.aws_region.current.region}"
          readonly postgresql_host="${var.postgresql_endpoint}"
          readonly postgresql_port="${var.postgresql_port}"
          readonly database_name="${local.database_name}"
          readonly app_username="${local.app_username}"
          readonly migration_username="${local.migration_username}"
          readonly admin_username_parameter="/lookddak/dev/v2/postgresql/admin/username"
          readonly admin_password_parameter="/lookddak/dev/v2/postgresql/admin/password"
          readonly app_password_parameter="${local.parameter_names.app_password}"
          readonly app_database_url_parameter="${local.parameter_names.app_database_url}"
          readonly app_checkpoint_dsn_parameter="${local.parameter_names.app_checkpoint_dsn}"
          readonly migration_password_parameter="${local.parameter_names.migration_password}"

          admin_username=""
          admin_password=""
          app_password=""
          migration_password=""
          app_database_url=""
          app_checkpoint_dsn=""

          cleanup() {
            unset admin_password app_password migration_password app_database_url app_checkpoint_dsn PGPASSWORD PGOPTIONS
          }
          trap cleanup EXIT

          get_parameter() {
            aws ssm get-parameter \
              --region "$${aws_region}" \
              --name "$1" \
              --with-decryption \
              --query 'Parameter.Value' \
              --output text
          }

          put_secure_parameter() {
            local parameter_name="$1"
            local description="$2"
            local credential_type="$3"
            local parameter_value="$4"

            printf '%s' "$${parameter_value}" | aws ssm put-parameter \
              --region "$${aws_region}" \
              --name "$${parameter_name}" \
              --description "$${description}" \
              --type SecureString \
              --value file:///dev/stdin \
              --tier Standard \
              --data-type text \
              --overwrite \
              >/dev/null

            aws ssm add-tags-to-resource \
              --region "$${aws_region}" \
              --resource-type Parameter \
              --resource-id "$${parameter_name}" \
              --tags \
                Key=CredentialType,Value="$${credential_type}" \
                Key=Environment,Value=dev \
                Key=Service,Value=postgresql \
                Key=Version,Value=v3 \
              >/dev/null
          }

          admin_psql() {
            local target_database="$1"
            shift
            PGOPTIONS='-c log_statement=none' PGPASSWORD="$${admin_password}" psql \
              --host="$${postgresql_host}" \
              --port="$${postgresql_port}" \
              --username="$${admin_username}" \
              --dbname="$${target_database}" \
              --set=ON_ERROR_STOP=1 \
              --no-psqlrc \
              "$@"
          }

          role_password_works() {
            local role_name="$1"
            local role_password="$2"
            PGPASSWORD="$${role_password}" psql \
              --host="$${postgresql_host}" \
              --port="$${postgresql_port}" \
              --username="$${role_name}" \
              --dbname=postgres \
              --set=ON_ERROR_STOP=1 \
              --no-psqlrc \
              --tuples-only \
              --command='SELECT 1' \
              >/dev/null 2>&1
          }

          if ! command -v psql >/dev/null 2>&1 || ! command -v createdb >/dev/null 2>&1; then
            dnf install -y postgresql15 >/dev/null
          fi

          admin_username="$(get_parameter "$${admin_username_parameter}")"
          admin_password="$(get_parameter "$${admin_password_parameter}")"

          admin_psql postgres --tuples-only --command='SELECT 1' >/dev/null

          # Role은 먼저 비밀번호 없이 만들고, 아래 전용 세션에서만 비밀번호를 설정한다.
          # PGOPTIONS로 statement logging을 끄므로 RDS PostgreSQL 로그에 비밀번호가 남지 않는다.
          admin_psql postgres <<'SQL'
          DO $$
          BEGIN
            IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '${local.app_username}') THEN
              CREATE ROLE ${local.app_username} LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION;
            END IF;
            IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '${local.migration_username}') THEN
              CREATE ROLE ${local.migration_username} LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION;
            END IF;
          END
          $$;
          SQL

          app_password="$(get_parameter "$${app_password_parameter}" 2>/dev/null || true)"
          if [[ "$${#app_password}" -lt 32 ]]; then
            app_password="$(openssl rand -hex 32)"
          fi
          if ! role_password_works "$${app_username}" "$${app_password}"; then
            admin_psql postgres <<SQL
          ALTER ROLE ${local.app_username} WITH LOGIN PASSWORD '$${app_password}';
          SQL
          fi
          put_secure_parameter \
            "$${app_password_parameter}" \
            "LookDDak Dev V3 PostgreSQL application password" \
            app \
            "$${app_password}"

          migration_password="$(get_parameter "$${migration_password_parameter}" 2>/dev/null || true)"
          if [[ "$${#migration_password}" -lt 32 ]]; then
            migration_password="$(openssl rand -hex 32)"
          fi
          if ! role_password_works "$${migration_username}" "$${migration_password}"; then
            admin_psql postgres <<SQL
          ALTER ROLE ${local.migration_username} WITH LOGIN PASSWORD '$${migration_password}';
          SQL
          fi
          put_secure_parameter \
            "$${migration_password_parameter}" \
            "LookDDak Dev V3 PostgreSQL migration password" \
            migration \
            "$${migration_password}"

          if [[ "$(admin_psql postgres --tuples-only --no-align --command="SELECT 1 FROM pg_database WHERE datname = '$${database_name}'")" != "1" ]]; then
            PGOPTIONS='-c log_statement=none' PGPASSWORD="$${admin_password}" createdb \
              --host="$${postgresql_host}" \
              --port="$${postgresql_port}" \
              --username="$${admin_username}" \
              --owner="$${migration_username}" \
              --encoding=UTF8 \
              "$${database_name}"
          fi

          admin_psql postgres <<'SQL'
          ALTER DATABASE ${local.database_name} OWNER TO ${local.migration_username};
          REVOKE ALL ON DATABASE ${local.database_name} FROM PUBLIC;
          GRANT CONNECT, TEMPORARY ON DATABASE ${local.database_name} TO ${local.app_username};
          GRANT ALL PRIVILEGES ON DATABASE ${local.database_name} TO ${local.migration_username};
          ALTER DATABASE ${local.database_name} SET timezone TO 'UTC';
          SQL

          admin_psql "$${database_name}" <<'SQL'
          REVOKE CREATE ON SCHEMA public FROM PUBLIC;
          ALTER SCHEMA public OWNER TO ${local.migration_username};
          GRANT USAGE ON SCHEMA public TO ${local.app_username};
          GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO ${local.app_username};
          GRANT USAGE, SELECT, UPDATE ON ALL SEQUENCES IN SCHEMA public TO ${local.app_username};
          ALTER DEFAULT PRIVILEGES FOR ROLE ${local.migration_username} IN SCHEMA public
            GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO ${local.app_username};
          ALTER DEFAULT PRIVILEGES FOR ROLE ${local.migration_username} IN SCHEMA public
            GRANT USAGE, SELECT, UPDATE ON SEQUENCES TO ${local.app_username};

          CREATE SCHEMA IF NOT EXISTS langgraph AUTHORIZATION ${local.migration_username};
          ALTER SCHEMA langgraph OWNER TO ${local.migration_username};
          GRANT USAGE, CREATE ON SCHEMA langgraph TO ${local.app_username};
          SQL

          app_database_url="postgresql://$${app_username}:$${app_password}@$${postgresql_host}:$${postgresql_port}/$${database_name}?sslmode=require"
          app_checkpoint_dsn="postgresql://$${app_username}:$${app_password}@$${postgresql_host}:$${postgresql_port}/$${database_name}?sslmode=require&options=-csearch_path%3Dlanggraph"

          put_secure_parameter \
            "$${app_database_url_parameter}" \
            "LookDDak Dev V3 PostgreSQL application database URL" \
            connection \
            "$${app_database_url}"
          put_secure_parameter \
            "$${app_checkpoint_dsn_parameter}" \
            "LookDDak Dev V3 PostgreSQL LangGraph checkpoint DSN" \
            connection \
            "$${app_checkpoint_dsn}"

          PGPASSWORD="$${app_password}" psql \
            --host="$${postgresql_host}" \
            --port="$${postgresql_port}" \
            --username="$${app_username}" \
            --dbname="$${database_name}" \
            --set=ON_ERROR_STOP=1 \
            --no-psqlrc \
            --command='SELECT 1' \
            >/dev/null

          PGPASSWORD="$${migration_password}" psql \
            --host="$${postgresql_host}" \
            --port="$${postgresql_port}" \
            --username="$${migration_username}" \
            --dbname="$${database_name}" \
            --set=ON_ERROR_STOP=1 \
            --no-psqlrc \
            --command='SELECT 1' \
            >/dev/null

          echo "V3 PostgreSQL Database와 전용 사용자의 구성이 완료됐습니다."
        SHELL
        ]
      }
    }]
  })

  tags = local.common_tags

  depends_on = [aws_iam_role_policy.bootstrap_parameters]
}
