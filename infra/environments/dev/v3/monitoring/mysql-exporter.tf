data "aws_iam_policy_document" "mysql_exporter_bootstrap" {
  statement {
    sid     = "ReadBootstrapParameters"
    actions = ["ssm:GetParameter"]
    resources = [
      "${local.ssm_parameter_arn_prefix}/lookddak/dev/rds/admin/username",
      "${local.ssm_parameter_arn_prefix}/lookddak/dev/rds/admin/password",
      "${local.ssm_parameter_arn_prefix}${local.mysql_exporter.password_parameter}",
    ]
  }

  statement {
    sid = "CreateExporterPassword"
    actions = [
      "ssm:AddTagsToResource",
      "ssm:PutParameter",
    ]
    resources = ["${local.ssm_parameter_arn_prefix}${local.mysql_exporter.password_parameter}"]
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
      values   = ["ssm.${local.region}.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "mysql_exporter_bootstrap" {
  name   = "${var.name_prefix}-mysql-exporter-bootstrap"
  role   = var.db_access_instance_role_name
  policy = data.aws_iam_policy_document.mysql_exporter_bootstrap.json
}

resource "aws_ssm_document" "mysql_exporter_bootstrap" {
  name            = "${var.name_prefix}-mysql-exporter-bootstrap"
  document_type   = "Command"
  document_format = "JSON"

  content = jsonencode({
    schemaVersion = "2.2"
    description   = "Create the LookDdak Dev V3 MySQL exporter user for in-cluster Alloy"
    mainSteps = [{
      action = "aws:runShellScript"
      name   = "bootstrapV3MysqlExporter"
      inputs = {
        timeoutSeconds = "600"
        runCommand = [<<-SHELL
          #!/bin/bash
          set -euo pipefail
          umask 077

          readonly aws_region="${local.region}"
          readonly mysql_host="${var.mysql_endpoint}"
          readonly exporter_username="${local.mysql_exporter.username}"
          readonly exporter_host="${local.mysql_exporter.client_host}"
          readonly admin_username_parameter="/lookddak/dev/rds/admin/username"
          readonly admin_password_parameter="/lookddak/dev/rds/admin/password"
          readonly exporter_password_parameter="${local.mysql_exporter.password_parameter}"

          admin_username=""
          admin_password=""
          exporter_password=""

          cleanup() {
            unset admin_username admin_password exporter_password
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

          admin_sql() {
            MYSQL_PWD="$${admin_password}" "$${mysql_client}" \
              --host="$${mysql_host}" \
              --port=3306 \
              --user="$${admin_username}" \
              --ssl \
              --batch \
              --raw \
              --skip-column-names \
              "$@"
          }

          user_count="$(admin_sql --execute="SELECT COUNT(*) FROM mysql.user WHERE user='$${exporter_username}' AND host='$${exporter_host}'")"

          admin_sql >/dev/null <<SQL
          CREATE USER IF NOT EXISTS '$${exporter_username}'@'$${exporter_host}'
            IDENTIFIED BY RANDOM PASSWORD
            REQUIRE SSL
            WITH MAX_USER_CONNECTIONS 3;
          GRANT PROCESS, REPLICATION CLIENT ON *.* TO '$${exporter_username}'@'$${exporter_host}';
          GRANT SELECT ON performance_schema.* TO '$${exporter_username}'@'$${exporter_host}';
          SQL

          rotate_password=true
          if [[ "$${user_count}" == "1" ]] && \
            exporter_password="$(get_parameter "$${exporter_password_parameter}" 2>/dev/null)" && \
            [[ "$${#exporter_password}" -ge 16 ]]; then
            rotate_password=false
          fi

          if [[ "$${rotate_password}" == "true" ]]; then
            exporter_password="$(
              admin_sql --execute="ALTER USER '$${exporter_username}'@'$${exporter_host}' IDENTIFIED BY RANDOM PASSWORD" \
              | awk -F '\t' 'NF >= 3 { print $3 }' \
              | tail -n 1
            )"

            if [[ "$${#exporter_password}" -lt 16 ]]; then
              echo "MySQL이 안전한 exporter 비밀번호를 반환하지 않았습니다." >&2
              exit 1
            fi

            printf '%s' "$${exporter_password}" | aws ssm put-parameter \
              --region "$${aws_region}" \
              --name "$${exporter_password_parameter}" \
              --description "LookDDak Dev V3 MySQL exporter password (in-cluster Alloy)" \
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
            --resource-id "$${exporter_password_parameter}" \
            --tags \
              Key=CredentialType,Value=monitoring \
              Key=Environment,Value=dev \
              Key=Service,Value=mysql \
              Key=Version,Value=v3 \
            >/dev/null

          echo "V3 MySQL exporter 사용자 구성이 완료됐습니다."
        SHELL
        ]
      }
    }]
  })

  tags = local.common_tags

  depends_on = [aws_iam_role_policy.mysql_exporter_bootstrap]
}
