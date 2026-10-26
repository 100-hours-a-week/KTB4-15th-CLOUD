# ---------------------------------------------------------------
# Grafana 인증: ALB authenticate-cognito → Grafana (auth proxy)
# - 인터넷 요청은 ALB에서 Cognito 로그인을 거쳐야 Grafana로 전달된다.
# - ALB는 Cognito 사용자 ID(sub, UUID)를 X-Amzn-Oidc-Identity 헤더로 넘기고,
#   Grafana auth proxy가 이 값으로 사용자를 만들고 로그인시킨다.
# - 사용자는 관리자가 직접 만든다 (셀프 가입 없음). 로그인 ID는 이메일.
# - sub는 사용자 풀이 바뀌면 전부 새로 생긴다 → 삭제 보호를 켠다.
#   username_attributes 등 일부 속성은 바꾸면 사용자 풀이 교체되니 주의.
# - 앱 클라이언트 시크릿은 Terraform state(S3)에만 있다. ALB가 직접 사용한다.
# ---------------------------------------------------------------
resource "aws_cognito_user_pool" "grafana" {
  name                = "lookddak-${var.environment}-grafana"
  deletion_protection = "ACTIVE"

  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  admin_create_user_config {
    allow_admin_create_user_only = true
  }

  password_policy {
    minimum_length                   = 12
    require_lowercase                = true
    require_uppercase                = true
    require_numbers                  = true
    require_symbols                  = false
    temporary_password_validity_days = 7
  }

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  tags = local.common_tags
}

# 로그인 페이지: https://lookddak-dev-grafana.auth.ap-northeast-2.amazoncognito.com
resource "aws_cognito_user_pool_domain" "grafana" {
  domain       = "lookddak-${var.environment}-grafana"
  user_pool_id = aws_cognito_user_pool.grafana.id
}

resource "aws_cognito_user_pool_client" "grafana_alb" {
  name         = "lookddak-${var.environment}-grafana-alb"
  user_pool_id = aws_cognito_user_pool.grafana.id

  generate_secret                      = true
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["openid", "email"]
  supported_identity_providers         = ["COGNITO"]
  callback_urls                        = ["https://${var.grafana_domain_name}/oauth2/idpresponse"]
  # Cognito 로그아웃 후 돌아올 주소 (grafana-logout.tf)
  logout_urls = ["https://${var.grafana_domain_name}/"]

  explicit_auth_flows = [
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_USER_SRP_AUTH",
  ]

  prevent_user_existence_errors = "ENABLED"
}

# --- ALB 규칙: grafana 도메인 → Cognito 인증 → Grafana ---
# 호스트가 달라 기존 규칙(5, 10, 20, 30)과 겹치지 않는다.
resource "aws_lb_listener_rule" "grafana" {
  listener_arn = var.https_listener_arn
  priority     = var.grafana_listener_rule_priority

  action {
    type = "authenticate-cognito"

    authenticate_cognito {
      user_pool_arn              = aws_cognito_user_pool.grafana.arn
      user_pool_client_id        = aws_cognito_user_pool_client.grafana_alb.id
      user_pool_domain           = aws_cognito_user_pool_domain.grafana.domain
      on_unauthenticated_request = "authenticate"
      scope                      = "openid email"
      session_timeout            = 43200 # 12시간
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.grafana.arn
  }

  condition {
    host_header {
      values = [var.grafana_domain_name]
    }
  }

  # CloudFront 경유(prod)면 원본 검증 헤더가 있어야 한다 (ALB 직접 접근 차단)
  dynamic "condition" {
    for_each = var.grafana_cloudfront_enabled ? [1] : []

    content {
      http_header {
        http_header_name = var.grafana_origin_verify_header_name
        values           = [var.grafana_origin_verify_header_value]
      }
    }
  }

  tags = merge(local.common_tags, {
    Name = "lookddak-${var.environment}-v2-grafana"
  })

  depends_on = [aws_lb_listener_certificate.grafana]
}

# ALB가 로그인 후 Cognito 토큰 엔드포인트를 직접 호출한다 (인터넷 443).
# 막혀 있으면 로그인 직후 500 오류가 난다.
resource "aws_vpc_security_group_egress_rule" "alb_to_cognito" {
  security_group_id = var.alb_security_group_id
  description       = "Cognito token and userinfo endpoints for ALB authentication"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}
