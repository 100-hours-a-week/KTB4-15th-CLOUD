resource "aws_cognito_user_pool_client" "grafana" {
  name         = "${var.name_prefix}-grafana"
  user_pool_id = var.grafana_user_pool_id

  generate_secret                      = true
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["openid", "email"]
  supported_identity_providers         = ["COGNITO"]
  callback_urls                        = ["https://${var.grafana_domain_name}/oauth2/callback"]
  logout_urls                          = ["https://${var.grafana_domain_name}/"]

  explicit_auth_flows = [
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_USER_SRP_AUTH",
  ]

  prevent_user_existence_errors = "ENABLED"
}

resource "random_password" "oauth2_proxy_cookie_secret" {
  length  = 32
  special = false
}

resource "aws_ssm_parameter" "oauth2_proxy_client_secret" {
  name        = local.oauth2_proxy_parameters.client_secret
  description = "LookDDak Prod V3 Grafana oauth2-proxy Cognito client secret"
  type        = "SecureString"
  value       = aws_cognito_user_pool_client.grafana.client_secret
  tier        = "Standard"

  tags = merge(local.common_tags, {
    CredentialType = "oauth"
  })
}

resource "aws_ssm_parameter" "oauth2_proxy_cookie_secret" {
  name        = local.oauth2_proxy_parameters.cookie_secret
  description = "LookDDak Prod V3 Grafana oauth2-proxy cookie secret"
  type        = "SecureString"
  value       = random_password.oauth2_proxy_cookie_secret.result
  tier        = "Standard"

  tags = merge(local.common_tags, {
    CredentialType = "oauth"
  })
}

data "aws_iam_policy_document" "oauth2_proxy" {
  statement {
    sid     = "ReadOauth2ProxySecrets"
    actions = ["ssm:GetParameters"]
    resources = [
      aws_ssm_parameter.oauth2_proxy_client_secret.arn,
      aws_ssm_parameter.oauth2_proxy_cookie_secret.arn,
    ]
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

resource "aws_iam_role_policy" "oauth2_proxy" {
  name   = "${var.name_prefix}-oauth2-proxy-secrets"
  role   = aws_iam_role.this["oauth2-proxy"].id
  policy = data.aws_iam_policy_document.oauth2_proxy.json
}
