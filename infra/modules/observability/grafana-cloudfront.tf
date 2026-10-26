# ---------------------------------------------------------------
# Grafana 외부 접속 (CloudFront 경유, prod)
# - grafana_cloudfront_enabled = true: grafana 도메인 → CloudFront → ALB(origin 도메인) → Monitoring EC2:3000
#   ALB 보안 그룹이 CloudFront 대역만 받는 환경(prod)용. dev는 ALB에 직접 붙는다 (grafana-alb.tf).
# - CloudFront는 Host 헤더를 그대로 넘긴다 (Managed-AllViewer).
#   ALB가 grafana 호스트 규칙으로 고르고, Cognito 로그인 후 돌아올 주소도 grafana 도메인이 된다.
#   CloudFront는 Host 값으로 ALB 인증서를 확인하므로 ALB에도 grafana 인증서가 있어야 한다 (grafana-alb.tf).
# - 원본 검증 헤더를 붙이고, Grafana 리스너 규칙도 이 헤더를 조건으로 건다 (ALB 직접 접근 차단).
# - WAF는 붙이지 않는다: Grafana API 요청이 관리형 규칙에 걸릴 수 있고, 로그인은 Cognito가 막는다.
# ---------------------------------------------------------------
locals {
  grafana_cloudfront_count = var.grafana_cloudfront_enabled ? 1 : 0
}

data "aws_cloudfront_cache_policy" "caching_disabled" {
  count = local.grafana_cloudfront_count
  name  = "Managed-CachingDisabled"
}

data "aws_cloudfront_origin_request_policy" "all_viewer" {
  count = local.grafana_cloudfront_count
  name  = "Managed-AllViewer"
}

# --- 뷰어 인증서 (CloudFront는 us-east-1 인증서만 쓴다) ---
resource "aws_acm_certificate" "grafana_viewer" {
  count    = local.grafana_cloudfront_count
  provider = aws.us_east_1

  domain_name       = var.grafana_domain_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(local.common_tags, {
    Name = "lookddak-${var.environment}-grafana-cloudfront"
  })
}

# 같은 도메인·계정이면 리전이 달라도 검증 레코드가 같다. grafana-alb.tf의 레코드를 만든 뒤 덮어쓴다(같은 값)
resource "aws_route53_record" "grafana_viewer_certificate_validation" {
  for_each = {
    for option in flatten(aws_acm_certificate.grafana_viewer[*].domain_validation_options) :
    option.domain_name => {
      name   = option.resource_record_name
      record = option.resource_record_value
      type   = option.resource_record_type
    }
  }

  allow_overwrite = true
  zone_id         = var.route53_zone_id
  name            = each.value.name
  type            = each.value.type
  ttl             = 300
  records         = [each.value.record]

  depends_on = [aws_route53_record.grafana_certificate_validation]
}

resource "aws_acm_certificate_validation" "grafana_viewer" {
  count    = local.grafana_cloudfront_count
  provider = aws.us_east_1

  certificate_arn         = aws_acm_certificate.grafana_viewer[0].arn
  validation_record_fqdns = [for record in aws_route53_record.grafana_viewer_certificate_validation : record.fqdn]
}

# --- CloudFront ---
resource "aws_cloudfront_distribution" "grafana" {
  count = local.grafana_cloudfront_count

  enabled         = true
  is_ipv6_enabled = true
  http_version    = "http2and3"
  price_class     = "PriceClass_200"
  comment         = "LookDDak ${var.environment} Grafana"
  aliases         = [var.grafana_domain_name]

  origin {
    domain_name = var.grafana_origin_domain_name
    origin_id   = "${local.name}-grafana"

    custom_header {
      name  = var.grafana_origin_verify_header_name
      value = var.grafana_origin_verify_header_value
    }

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
      origin_read_timeout    = 60
    }
  }

  default_cache_behavior {
    target_origin_id       = "${local.name}-grafana"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    cache_policy_id          = data.aws_cloudfront_cache_policy.caching_disabled[0].id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_viewer[0].id
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.grafana_viewer[0].certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  lifecycle {
    precondition {
      condition     = var.grafana_origin_domain_name != null && nonsensitive(var.grafana_origin_verify_header_value != null)
      error_message = "grafana_cloudfront_enabled requires grafana_origin_domain_name and grafana_origin_verify_header_value."
    }
  }

  # 원본(ALB)이 grafana 인증서와 규칙을 먼저 갖고 있어야 한다
  depends_on = [
    aws_lb_listener_certificate.grafana,
    aws_lb_listener_rule.grafana,
  ]

  tags = merge(local.common_tags, {
    Name = "lookddak-${var.environment}-grafana"
  })
}

resource "aws_route53_record" "grafana_ipv6" {
  count = local.grafana_cloudfront_count

  zone_id = var.route53_zone_id
  name    = var.grafana_domain_name
  type    = "AAAA"

  alias {
    name                   = aws_cloudfront_distribution.grafana[0].domain_name
    zone_id                = aws_cloudfront_distribution.grafana[0].hosted_zone_id
    evaluate_target_health = false
  }
}
