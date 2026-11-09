data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

data "aws_region" "current" {}

data "aws_kms_alias" "ssm" {
  name = "alias/aws/ssm"
}

locals {
  database_name                 = "lookddak"
  mysql_app_username            = "lookddak_v3_app"
  postgresql_app_username       = "lookddak_v3_app"
  postgresql_migration_username = "lookddak_v3_migration"

  parameter_names = {
    mysql_jdbc_url     = "/lookddak/prod/v3/mysql/jdbc-url"
    mysql_app_username = "/lookddak/prod/v3/mysql/app/username"
    mysql_app_password = "/lookddak/prod/v3/mysql/app/password"

    postgresql_host               = "/lookddak/prod/v3/postgresql/host"
    postgresql_port               = "/lookddak/prod/v3/postgresql/port"
    postgresql_database           = "/lookddak/prod/v3/postgresql/database"
    postgresql_app_username       = "/lookddak/prod/v3/postgresql/app/username"
    postgresql_app_password       = "/lookddak/prod/v3/postgresql/app/password"
    postgresql_app_database_url   = "/lookddak/prod/v3/postgresql/app/database-url"
    postgresql_app_checkpoint_dsn = "/lookddak/prod/v3/postgresql/app/checkpoint-dsn"
    postgresql_migration_username = "/lookddak/prod/v3/postgresql/migration/username"
    postgresql_migration_password = "/lookddak/prod/v3/postgresql/migration/password"
  }

  string_parameters = {
    mysql_jdbc_url = {
      name        = local.parameter_names.mysql_jdbc_url
      description = "LookDDak Prod V3 Spring JDBC URL on the shared Prod MySQL database"
      value       = "jdbc:mysql://${var.mysql_endpoint}:3306/${local.database_name}?sslMode=REQUIRED&serverTimezone=UTC&characterEncoding=UTF-8"
      component   = "mysql"
      credential  = "connection"
    }
    mysql_app_username = {
      name        = local.parameter_names.mysql_app_username
      description = "LookDDak Prod V3 MySQL application username"
      value       = local.mysql_app_username
      component   = "mysql"
      credential  = "app"
    }
    postgresql_host = {
      name        = local.parameter_names.postgresql_host
      description = "LookDDak Prod V3 shared PostgreSQL endpoint"
      value       = var.postgresql_endpoint
      component   = "postgresql"
      credential  = "connection"
    }
    postgresql_port = {
      name        = local.parameter_names.postgresql_port
      description = "LookDDak Prod V3 shared PostgreSQL port"
      value       = tostring(var.postgresql_port)
      component   = "postgresql"
      credential  = "connection"
    }
    postgresql_database = {
      name        = local.parameter_names.postgresql_database
      description = "LookDDak Prod V3 shared PostgreSQL database name"
      value       = local.database_name
      component   = "postgresql"
      credential  = "connection"
    }
    postgresql_app_username = {
      name        = local.parameter_names.postgresql_app_username
      description = "LookDDak Prod V3 PostgreSQL application username"
      value       = local.postgresql_app_username
      component   = "postgresql"
      credential  = "app"
    }
    postgresql_migration_username = {
      name        = local.parameter_names.postgresql_migration_username
      description = "LookDDak Prod V3 PostgreSQL migration username"
      value       = local.postgresql_migration_username
      component   = "postgresql"
      credential  = "migration"
    }
  }

  secure_parameter_names = [
    local.parameter_names.mysql_app_password,
    local.parameter_names.postgresql_app_password,
    local.parameter_names.postgresql_app_database_url,
    local.parameter_names.postgresql_app_checkpoint_dsn,
    local.parameter_names.postgresql_migration_password,
  ]

  parameter_arn_prefix = "arn:${data.aws_partition.current.partition}:ssm:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:parameter"

  common_tags = {
    Environment = "prod"
    Version     = "v3"
  }
}

# Prod V3 does not create or modify an RDS instance. It only opens the existing
# Single-AZ Prod V2 databases to ENIs that use the Prod V3 EKS Cluster SG.
resource "aws_vpc_security_group_ingress_rule" "mysql_from_v3_eks" {
  security_group_id            = var.mysql_security_group_id
  description                  = "MySQL traffic from Prod V3 EKS application workloads"
  ip_protocol                  = "tcp"
  from_port                    = 3306
  to_port                      = 3306
  referenced_security_group_id = var.eks_cluster_security_group_id

  tags = merge(local.common_tags, { Component = "mysql-access" })
}

resource "aws_vpc_security_group_ingress_rule" "postgresql_from_v3_eks" {
  security_group_id            = var.postgresql_security_group_id
  description                  = "PostgreSQL traffic from Prod V3 EKS application workloads"
  ip_protocol                  = "tcp"
  from_port                    = var.postgresql_port
  to_port                      = var.postgresql_port
  referenced_security_group_id = var.eks_cluster_security_group_id

  tags = merge(local.common_tags, { Component = "postgresql-access" })
}

resource "aws_ssm_parameter" "connection" {
  for_each = local.string_parameters

  name        = each.value.name
  description = each.value.description
  type        = "String"
  value       = each.value.value
  tier        = "Standard"
  data_type   = "text"

  tags = merge(local.common_tags, {
    Component      = each.value.component
    CredentialType = each.value.credential
  })
}

data "aws_iam_policy_document" "bootstrap_parameters" {
  statement {
    sid     = "ReadProdDatabaseBootstrapParameters"
    actions = ["ssm:GetParameter"]
    resources = concat([
      "${local.parameter_arn_prefix}/lookddak/prod/rds/admin/username",
      "${local.parameter_arn_prefix}/lookddak/prod/rds/admin/password",
      "${local.parameter_arn_prefix}/lookddak/prod/v2/postgresql/admin/username",
      "${local.parameter_arn_prefix}/lookddak/prod/v2/postgresql/admin/password",
      "${local.parameter_arn_prefix}/lookddak/prod/v2/postgresql/app/username",
      "${local.parameter_arn_prefix}/lookddak/prod/v2/postgresql/migration/username",
    ], [for name in local.secure_parameter_names : "${local.parameter_arn_prefix}${name}"])
  }

  statement {
    sid = "WriteProdV3DatabaseSecureParameters"
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
  name   = "lookddak-prod-v3-database-bootstrap-parameters"
  role   = var.db_access_instance_role_name
  policy = data.aws_iam_policy_document.bootstrap_parameters.json
}

resource "aws_ssm_document" "bootstrap" {
  name            = "lookddak-prod-v3-database-bootstrap"
  document_type   = "Command"
  document_format = "JSON"

  content = jsonencode({
    schemaVersion = "2.2"
    description   = "Create Prod V3 users on the existing Prod MySQL and PostgreSQL databases"
    mainSteps = [{
      action = "aws:runShellScript"
      name   = "bootstrapProdV3DatabaseUsers"
      inputs = {
        timeoutSeconds = "900"
        runCommand = [<<-SHELL
          #!/bin/bash
          set -euo pipefail
          set +x
          umask 077

          readonly aws_region="${data.aws_region.current.region}"
          readonly database_name="${local.database_name}"
          readonly mysql_host="${var.mysql_endpoint}"
          readonly mysql_app_username="${local.mysql_app_username}"
          readonly postgresql_host="${var.postgresql_endpoint}"
          readonly postgresql_port="${var.postgresql_port}"
          readonly postgresql_app_username="${local.postgresql_app_username}"
          readonly postgresql_migration_username="${local.postgresql_migration_username}"

          readonly mysql_admin_username_parameter="/lookddak/prod/rds/admin/username"
          readonly mysql_admin_password_parameter="/lookddak/prod/rds/admin/password"
          readonly mysql_app_password_parameter="${local.parameter_names.mysql_app_password}"
          readonly postgresql_admin_username_parameter="/lookddak/prod/v2/postgresql/admin/username"
          readonly postgresql_admin_password_parameter="/lookddak/prod/v2/postgresql/admin/password"
          readonly postgresql_v2_app_username_parameter="/lookddak/prod/v2/postgresql/app/username"
          readonly postgresql_v2_migration_username_parameter="/lookddak/prod/v2/postgresql/migration/username"
          readonly postgresql_app_password_parameter="${local.parameter_names.postgresql_app_password}"
          readonly postgresql_app_database_url_parameter="${local.parameter_names.postgresql_app_database_url}"
          readonly postgresql_app_checkpoint_dsn_parameter="${local.parameter_names.postgresql_app_checkpoint_dsn}"
          readonly postgresql_migration_password_parameter="${local.parameter_names.postgresql_migration_password}"

          mysql_admin_username=""
          mysql_admin_password=""
          mysql_app_password=""
          postgresql_admin_username=""
          postgresql_admin_password=""
          postgresql_v2_app_username=""
          postgresql_v2_migration_username=""
          postgresql_app_password=""
          postgresql_migration_password=""

          cleanup() {
            unset mysql_admin_password mysql_app_password postgresql_admin_password
            unset postgresql_app_password postgresql_migration_password PGPASSWORD PGOPTIONS MYSQL_PWD
          }
          trap cleanup EXIT

          get_parameter() {
            aws ssm get-parameter --region "$${aws_region}" --name "$1" --with-decryption \
              --query 'Parameter.Value' --output text
          }

          put_secure_parameter() {
            local parameter_name="$1"
            local description="$2"
            local credential_type="$3"
            local service="$4"
            local parameter_value="$5"

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
                Key=Environment,Value=prod \
                Key=Service,Value="$${service}" \
                Key=Version,Value=v3 \
              >/dev/null
          }

          if ! command -v mysql >/dev/null 2>&1 && ! command -v mariadb >/dev/null 2>&1; then
            dnf install -y mariadb105 >/dev/null
          fi
          if ! command -v psql >/dev/null 2>&1; then
            dnf install -y postgresql15 >/dev/null
          fi
          if command -v mysql >/dev/null 2>&1; then
            mysql_client="mysql"
          else
            mysql_client="mariadb"
          fi

          mysql_admin_username="$(get_parameter "$${mysql_admin_username_parameter}")"
          mysql_admin_password="$(get_parameter "$${mysql_admin_password_parameter}")"

          # The database already exists. Hibernate uses ddl-auto=update in prod, so
          # this account receives database-scoped DDL and DML privileges, never global privileges.
          MYSQL_PWD="$${mysql_admin_password}" "$${mysql_client}" \
            --host="$${mysql_host}" --port=3306 --user="$${mysql_admin_username}" --ssl \
            --batch --skip-column-names >/dev/null <<SQL
          CREATE USER IF NOT EXISTS '$${mysql_app_username}'@'%' IDENTIFIED BY RANDOM PASSWORD;
          GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, REFERENCES, INDEX, ALTER
            ON \`$${database_name}\`.* TO '$${mysql_app_username}'@'%';
          SQL

          if mysql_app_password="$(get_parameter "$${mysql_app_password_parameter}" 2>/dev/null)" && \
            MYSQL_PWD="$${mysql_app_password}" "$${mysql_client}" \
              --host="$${mysql_host}" --port=3306 --user="$${mysql_app_username}" --ssl \
              --database="$${database_name}" --execute='SELECT 1' >/dev/null 2>&1; then
            :
          else
            mysql_app_password="$(
              MYSQL_PWD="$${mysql_admin_password}" "$${mysql_client}" \
                --host="$${mysql_host}" --port=3306 --user="$${mysql_admin_username}" --ssl \
                --batch --raw --skip-column-names \
                --execute="ALTER USER '$${mysql_app_username}'@'%' IDENTIFIED BY RANDOM PASSWORD" \
              | awk -F '\t' 'NF >= 3 { print $3 }' | tail -n 1
            )"
            if [[ "$${#mysql_app_password}" -lt 16 ]]; then
              echo "MySQL did not return a safe Prod V3 application password." >&2
              exit 1
            fi
          fi
          put_secure_parameter "$${mysql_app_password_parameter}" \
            "LookDDak Prod V3 MySQL application password" app mysql "$${mysql_app_password}"

          postgresql_admin_username="$(get_parameter "$${postgresql_admin_username_parameter}")"
          postgresql_admin_password="$(get_parameter "$${postgresql_admin_password_parameter}")"
          postgresql_v2_app_username="$(get_parameter "$${postgresql_v2_app_username_parameter}")"
          postgresql_v2_migration_username="$(get_parameter "$${postgresql_v2_migration_username_parameter}")"

          admin_psql() {
            PGOPTIONS='-c log_statement=none' PGPASSWORD="$${postgresql_admin_password}" psql \
              --host="$${postgresql_host}" --port="$${postgresql_port}" \
              --username="$${postgresql_admin_username}" --dbname="$${database_name}" \
              --set=ON_ERROR_STOP=1 --no-psqlrc "$@"
          }

          role_password_works() {
            local role_name="$1"
            local role_password="$2"
            PGPASSWORD="$${role_password}" psql \
              --host="$${postgresql_host}" --port="$${postgresql_port}" \
              --username="$${role_name}" --dbname="$${database_name}" \
              --set=ON_ERROR_STOP=1 --no-psqlrc --tuples-only --command='SELECT 1' \
              >/dev/null 2>&1
          }

          admin_psql --tuples-only --command='SELECT 1' >/dev/null
          admin_psql <<SQL
          DO \$\$
          BEGIN
            IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '$${postgresql_v2_app_username}') THEN
              RAISE EXCEPTION 'Existing Prod V2 PostgreSQL app role is missing';
            END IF;
            IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '$${postgresql_v2_migration_username}') THEN
              RAISE EXCEPTION 'Existing Prod V2 PostgreSQL migration role is missing';
            END IF;
            IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '$${postgresql_app_username}') THEN
              CREATE ROLE ${local.postgresql_app_username} LOGIN INHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION;
            END IF;
            IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '$${postgresql_migration_username}') THEN
              CREATE ROLE ${local.postgresql_migration_username} LOGIN INHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION;
            END IF;
          END
          \$\$;
          GRANT "$${postgresql_v2_app_username}" TO ${local.postgresql_app_username};
          GRANT "$${postgresql_v2_migration_username}" TO ${local.postgresql_migration_username};
          SQL

          postgresql_app_password="$(get_parameter "$${postgresql_app_password_parameter}" 2>/dev/null || true)"
          if [[ "$${#postgresql_app_password}" -lt 32 ]] || \
            ! role_password_works "$${postgresql_app_username}" "$${postgresql_app_password}"; then
            postgresql_app_password="$(openssl rand -hex 32)"
            admin_psql <<SQL
          ALTER ROLE ${local.postgresql_app_username} WITH LOGIN PASSWORD '$${postgresql_app_password}';
          SQL
          fi

          postgresql_migration_password="$(get_parameter "$${postgresql_migration_password_parameter}" 2>/dev/null || true)"
          if [[ "$${#postgresql_migration_password}" -lt 32 ]] || \
            ! role_password_works "$${postgresql_migration_username}" "$${postgresql_migration_password}"; then
            postgresql_migration_password="$(openssl rand -hex 32)"
            admin_psql <<SQL
          ALTER ROLE ${local.postgresql_migration_username} WITH LOGIN PASSWORD '$${postgresql_migration_password}';
          SQL
          fi

          put_secure_parameter "$${postgresql_app_password_parameter}" \
            "LookDDak Prod V3 PostgreSQL application password" app postgresql "$${postgresql_app_password}"
          put_secure_parameter "$${postgresql_migration_password_parameter}" \
            "LookDDak Prod V3 PostgreSQL migration password" migration postgresql "$${postgresql_migration_password}"

          postgresql_app_database_url="postgresql://$${postgresql_app_username}:$${postgresql_app_password}@$${postgresql_host}:$${postgresql_port}/$${database_name}?sslmode=require"
          postgresql_app_checkpoint_dsn="postgresql://$${postgresql_app_username}:$${postgresql_app_password}@$${postgresql_host}:$${postgresql_port}/$${database_name}?sslmode=require&options=-csearch_path%3Dlanggraph"
          put_secure_parameter "$${postgresql_app_database_url_parameter}" \
            "LookDDak Prod V3 PostgreSQL application database URL" connection postgresql "$${postgresql_app_database_url}"
          put_secure_parameter "$${postgresql_app_checkpoint_dsn_parameter}" \
            "LookDDak Prod V3 PostgreSQL LangGraph checkpoint DSN" connection postgresql "$${postgresql_app_checkpoint_dsn}"

          MYSQL_PWD="$${mysql_app_password}" "$${mysql_client}" \
            --host="$${mysql_host}" --port=3306 --user="$${mysql_app_username}" --ssl \
            --database="$${database_name}" --execute='SELECT 1' >/dev/null
          role_password_works "$${postgresql_app_username}" "$${postgresql_app_password}"
          role_password_works "$${postgresql_migration_username}" "$${postgresql_migration_password}"

          echo "Prod V3 shared database users and parameters are ready."
        SHELL
        ]
      }
    }]
  })

  tags = merge(local.common_tags, { Component = "database-bootstrap" })

  depends_on = [aws_iam_role_policy.bootstrap_parameters]
}
