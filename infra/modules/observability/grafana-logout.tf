# ---------------------------------------------------------------
# Grafana 로그아웃: grafana 도메인 /logout → Lambda → Cognito 로그아웃 → 로그인 페이지
# - Grafana 로그아웃 버튼은 /logout으로 간다. ALB가 이 경로만 Grafana보다 먼저 가로챈다.
# - Lambda가 ALB 인증 쿠키·Grafana 세션 쿠키를 만료시키고 Cognito 로그아웃으로 보낸다.
#   Cognito 로그인 상태까지 끝나야 다시 접속할 때 비밀번호를 묻는다.
# - 이 규칙에는 인증 액션이 없다 (로그아웃에 로그인이 필요 없음). 응답은 쿠키 삭제와 리다이렉트뿐.
# - 소스: lambda/grafana_logout/ (Terraform이 zip으로 묶어 배포)
# ---------------------------------------------------------------
locals {
  grafana_logout_name = "lookddak-${var.environment}-grafana-logout"
  grafana_url         = "https://${var.grafana_domain_name}/"
  cognito_logout_url  = "https://${aws_cognito_user_pool_domain.grafana.domain}.auth.${data.aws_region.current.region}.amazoncognito.com/logout?client_id=${aws_cognito_user_pool_client.grafana_alb.id}&logout_uri=${urlencode(local.grafana_url)}"
}

data "archive_file" "grafana_logout" {
  type        = "zip"
  source_dir  = "${path.module}/lambda/grafana_logout"
  output_path = "${path.module}/.build/grafana_logout.zip"
  excludes    = ["**/__pycache__/**"]
}

resource "aws_iam_role" "grafana_logout" {
  name        = "${local.grafana_logout_name}-role"
  description = "LookDDak ${var.environment} Grafana logout Lambda execution role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "grafana_logout_basic" {
  role       = aws_iam_role.grafana_logout.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_cloudwatch_log_group" "grafana_logout" {
  name              = "/aws/lambda/${local.grafana_logout_name}"
  retention_in_days = 3

  tags = local.common_tags
}

resource "aws_lambda_function" "grafana_logout" {
  function_name = local.grafana_logout_name
  description   = "Clear ALB auth and Grafana session cookies, then redirect to Cognito logout"
  role          = aws_iam_role.grafana_logout.arn
  runtime       = "python3.14"
  handler       = "lambda_function.lambda_handler"
  architectures = ["x86_64"]
  memory_size   = 128
  timeout       = 3

  filename         = data.archive_file.grafana_logout.output_path
  source_code_hash = data.archive_file.grafana_logout.output_base64sha256

  environment {
    variables = {
      COGNITO_LOGOUT_URL = local.cognito_logout_url
    }
  }

  tags = local.common_tags

  depends_on = [
    aws_cloudwatch_log_group.grafana_logout,
    aws_iam_role_policy_attachment.grafana_logout_basic,
  ]
}

# --- ALB → Lambda ---
# Set-Cookie를 여러 개 내려야 해서 multi value headers를 켠다.
resource "aws_lb_target_group" "grafana_logout" {
  name                               = local.grafana_logout_name
  target_type                        = "lambda"
  lambda_multi_value_headers_enabled = true

  tags = merge(local.common_tags, {
    Name = local.grafana_logout_name
  })
}

resource "aws_lambda_permission" "grafana_logout_alb" {
  statement_id  = "AllowALBInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.grafana_logout.function_name
  principal     = "elasticloadbalancing.amazonaws.com"
  source_arn    = aws_lb_target_group.grafana_logout.arn
}

resource "aws_lb_target_group_attachment" "grafana_logout" {
  target_group_arn = aws_lb_target_group.grafana_logout.arn
  target_id        = aws_lambda_function.grafana_logout.arn

  depends_on = [aws_lambda_permission.grafana_logout_alb]
}

# Grafana 규칙(40)보다 먼저 평가되도록 39
resource "aws_lb_listener_rule" "grafana_logout" {
  listener_arn = var.https_listener_arn
  priority     = var.grafana_logout_listener_rule_priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.grafana_logout.arn
  }

  condition {
    host_header {
      values = [var.grafana_domain_name]
    }
  }

  condition {
    path_pattern {
      values = ["/logout"]
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
    Name = local.grafana_logout_name
  })

  depends_on = [aws_lb_target_group_attachment.grafana_logout]
}
