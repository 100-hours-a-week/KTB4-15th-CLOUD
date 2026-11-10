resource "random_password" "redis_readonly" {
  length  = 40
  special = false
}

resource "aws_ssm_parameter" "redis_readonly_password" {
  name        = local.redis_readonly.password_parameter
  description = "LookDDak Prod V3 Redis read-only ACL user (${local.redis_readonly.username}) password for Grafana"
  type        = "SecureString"
  value       = random_password.redis_readonly.result
  tier        = "Standard"

  tags = merge(local.common_tags, {
    CredentialType = "redis"
  })
}

data "aws_iam_policy_document" "grafana" {
  statement {
    sid       = "ReadRedisReadonlyPassword"
    actions   = ["ssm:GetParameters"]
    resources = [aws_ssm_parameter.redis_readonly_password.arn]
  }

  statement {
    sid       = "DescribeParameters"
    actions   = ["ssm:DescribeParameters"]
    resources = ["*"]
  }

  statement {
    sid       = "DecryptParametersViaSsm"
    actions   = ["kms:Decrypt"]
    resources = [data.aws_kms_alias.ssm.target_key_arn]

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["ssm.${local.region}.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "grafana" {
  name   = "${var.name_prefix}-grafana-secrets"
  role   = aws_iam_role.this["grafana"].id
  policy = data.aws_iam_policy_document.grafana.json
}
