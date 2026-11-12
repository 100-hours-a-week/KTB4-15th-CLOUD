data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

data "aws_region" "current" {}

data "aws_kms_alias" "ssm" {
  name = "alias/aws/ssm"
}

locals {
  database_name = "lookddak"
  app_username  = "lookddak_v3_app"

  parameter_names = {
    jdbc_url     = "/lookddak/dev/v3/mysql/jdbc-url"
    app_username = "/lookddak/dev/v3/mysql/app/username"
    app_password = "/lookddak/dev/v3/mysql/app/password"
  }

  parameter_arn_prefix = "arn:${data.aws_partition.current.partition}:ssm:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:parameter"

  common_tags = {
    Component   = "mysql"
    Environment = "dev"
    Version     = "v3"
  }
}

# Karpenter Application Node와 Cilium Pod ENI가 사용하는 EKS Cluster SG에서만
# 기존 Dev MySQL의 3306 포트에 접근할 수 있게 한다.
resource "aws_vpc_security_group_ingress_rule" "mysql_from_v3_eks" {
  security_group_id            = var.mysql_security_group_id
  description                  = "MySQL traffic from V3 EKS application workloads"
  ip_protocol                  = "tcp"
  from_port                    = 3306
  to_port                      = 3306
  referenced_security_group_id = var.eks_cluster_security_group_id

  tags = local.common_tags
}

# JDBC URL과 사용자명은 비밀 값이 아니므로 Terraform으로 관리한다.
resource "aws_ssm_parameter" "jdbc_url" {
  name        = local.parameter_names.jdbc_url
  description = "LookDDak Dev V3 Spring JDBC URL on the shared MySQL RDS instance"
  type        = "String"
  value       = "jdbc:mysql://${var.mysql_endpoint}:3306/${local.database_name}?sslMode=REQUIRED&serverTimezone=UTC&characterEncoding=UTF-8"
  tier        = "Standard"
  data_type   = "text"

  tags = merge(local.common_tags, {
    CredentialType = "connection"
  })
}

resource "aws_ssm_parameter" "app_username" {
  name        = local.parameter_names.app_username
  description = "LookDDak Dev V3 MySQL application username"
  type        = "String"
  value       = local.app_username
  tier        = "Standard"
  data_type   = "text"

  tags = merge(local.common_tags, {
    CredentialType = "app"
  })
}

# DB Access Node는 V3 Database 초기화에 필요한 Parameter만 읽고,
# V3 앱 비밀번호 경로 하나에만 SecureString을 생성할 수 있다.
data "aws_iam_policy_document" "bootstrap_parameters" {
  statement {
    sid = "ReadBootstrapParameters"
    actions = [
      "ssm:GetParameter",
    ]
    resources = [
      "${local.parameter_arn_prefix}/lookddak/dev/rds/admin/username",
      "${local.parameter_arn_prefix}/lookddak/dev/rds/admin/password",
      "${local.parameter_arn_prefix}${local.parameter_names.app_password}",
    ]
  }

  statement {
    sid = "CreateV3ApplicationPassword"
    actions = [
      "ssm:AddTagsToResource",
      "ssm:PutParameter",
    ]
    resources = [
      "${local.parameter_arn_prefix}${local.parameter_names.app_password}",
    ]
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
  name   = "lookddak-dev-v3-mysql-bootstrap-parameters"
  role   = var.db_access_instance_role_name
  policy = data.aws_iam_policy_document.bootstrap_parameters.json
}

# Terraform은 RDS 내부 Database와 사용자를 직접 관리할 수 없으므로,
# Private DB Access Node에서 최초 1회 실행할 멱등 SSM Runbook을 제공한다.
resource "aws_ssm_document" "bootstrap" {
  name            = "lookddak-dev-v3-mysql-bootstrap"
  document_type   = "Command"
  document_format = "JSON"

  content = jsonencode({
    schemaVersion = "2.2"
    description   = "Create the isolated LookDdak Dev V3 MySQL database and application user"
    mainSteps = [{
      action = "aws:runShellScript"
      name   = "bootstrapV3Mysql"
      inputs = {
        timeoutSeconds = "900"
        runCommand = [<<-SHELL
          #!/bin/bash
          set -euo pipefail
          umask 077

          readonly aws_region="${data.aws_region.current.region}"
          readonly mysql_host="${var.mysql_endpoint}"
          readonly database_name="${local.database_name}"
          # DB 단위 GRANT에서 밑줄을 일반 문자로 처리한다.
          readonly grant_database_name="$${database_name//_/\\_}"
          readonly app_username="${local.app_username}"
          readonly admin_username_parameter="/lookddak/dev/rds/admin/username"
          readonly admin_password_parameter="/lookddak/dev/rds/admin/password"
          readonly app_password_parameter="${local.parameter_names.app_password}"

          admin_username=""
          admin_password=""
          app_password=""

          cleanup() {
            unset admin_username admin_password app_password
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

          admin_username="$(get_parameter "$${admin_username_parameter}")"
          admin_password="$(get_parameter "$${admin_password_parameter}")"

          if ! command -v mysql >/dev/null 2>&1 && ! command -v mariadb >/dev/null 2>&1; then
            dnf install -y mariadb105 >/dev/null
          fi

          if command -v mysql >/dev/null 2>&1; then
            mysql_client="mysql"
          else
            mysql_client="mariadb"
          fi

          MYSQL_PWD="$${admin_password}" "$${mysql_client}" \
            --host="$${mysql_host}" \
            --port=3306 \
            --user="$${admin_username}" \
            --ssl \
            --batch \
            --skip-column-names \
            >/dev/null <<SQL
          CREATE USER IF NOT EXISTS '$${app_username}'@'%'
            IDENTIFIED BY RANDOM PASSWORD;
          GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, REFERENCES, INDEX, ALTER
            ON \`$${grant_database_name}\`.* TO '$${app_username}'@'%';
          SQL

          # 기존 SecureString으로 로그인이 되면 비밀번호를 회전하지 않는다.
          # Parameter가 없거나 DB 비밀번호와 다를 때만 MySQL이 새 값을 생성한다.
          if app_password="$(get_parameter "$${app_password_parameter}" 2>/dev/null)" && \
            MYSQL_PWD="$${app_password}" "$${mysql_client}" \
              --host="$${mysql_host}" \
              --port=3306 \
              --user="$${app_username}" \
              --ssl \
              --database="$${database_name}" \
              --execute='SELECT 1' \
              >/dev/null 2>&1; then
            :
          else
            # RANDOM PASSWORD를 사용해 Audit Log의 SQL 원문에 비밀번호가 남지 않게 한다.
            app_password="$(
              MYSQL_PWD="$${admin_password}" "$${mysql_client}" \
                --host="$${mysql_host}" \
                --port=3306 \
                --user="$${admin_username}" \
                --ssl \
                --batch \
                --raw \
                --skip-column-names \
                --execute="ALTER USER '$${app_username}'@'%' IDENTIFIED BY RANDOM PASSWORD" \
              | awk -F '\t' 'NF >= 3 { print $3 }' \
              | tail -n 1
            )"

            if [[ "$${#app_password}" -lt 16 ]]; then
              echo "MySQL이 안전한 V3 앱 비밀번호를 반환하지 않았습니다." >&2
              exit 1
            fi

            # 비밀번호를 프로세스 인자에 포함하지 않고 표준 입력으로 전달한다.
            printf '%s' "$${app_password}" | aws ssm put-parameter \
              --region "$${aws_region}" \
              --name "$${app_password_parameter}" \
              --description "LookDDak Dev V3 MySQL application password" \
              --type SecureString \
              --value file:///dev/stdin \
              --tier Standard \
              --data-type text \
              --overwrite \
              >/dev/null
          fi

          aws ssm add-tags-to-resource \
            --region "$${aws_region}" \
            --resource-type Parameter \
            --resource-id "$${app_password_parameter}" \
            --tags \
              Key=CredentialType,Value=app \
              Key=Environment,Value=dev \
              Key=Service,Value=mysql \
              Key=Version,Value=v3 \
            >/dev/null

          MYSQL_PWD="$${app_password}" "$${mysql_client}" \
            --host="$${mysql_host}" \
            --port=3306 \
            --user="$${app_username}" \
            --ssl \
            --database="$${database_name}" \
            --execute='SELECT 1' \
            >/dev/null

          echo "V3 MySQL Database와 전용 앱 사용자 구성이 완료됐습니다."
        SHELL
        ]
      }
    }]
  })

  tags = local.common_tags

  depends_on = [aws_iam_role_policy.bootstrap_parameters]
}
