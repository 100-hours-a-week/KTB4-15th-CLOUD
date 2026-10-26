data "aws_cloudfront_cache_policy" "caching_disabled" {
  name = "Managed-CachingDisabled"
}

data "aws_cloudfront_cache_policy" "caching_optimized" {
  name = "Managed-CachingOptimized"
}

data "aws_cloudfront_origin_request_policy" "all_viewer_except_host" {
  name = "Managed-AllViewerExceptHostHeader"
}

locals {
  common_tags = {
    Environment = "prod"
    Version     = "v2"
    Component   = "edge"
  }
}

resource "random_password" "origin_verify" {
  length  = 32
  special = false
}

# -----------------------------------------------------------------------------
# Regional certificate and ALB origin
# -----------------------------------------------------------------------------
resource "aws_acm_certificate" "origin" {
  domain_name       = var.origin_domain_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(local.common_tags, {
    Name = "lookddak-prod-v2-origin"
  })
}

resource "aws_route53_record" "origin_certificate_validation" {
  for_each = {
    for option in aws_acm_certificate.origin.domain_validation_options :
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
}

resource "aws_acm_certificate_validation" "origin" {
  certificate_arn         = aws_acm_certificate.origin.arn
  validation_record_fqdns = [for record in aws_route53_record.origin_certificate_validation : record.fqdn]
}

resource "aws_lb" "this" {
  name               = "lookddak-prod-v2-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.alb_security_group_id]
  subnets            = var.public_subnet_ids
  ip_address_type    = "ipv4"
  idle_timeout       = 120

  # 액세스 로그 → S3 (5분마다 파일). 버킷은 observability 모듈이 만든다.
  dynamic "access_logs" {
    for_each = var.access_logs_bucket == null ? [] : [var.access_logs_bucket]

    content {
      bucket  = access_logs.value
      prefix  = "alb"
      enabled = true
    }
  }

  tags = merge(local.common_tags, {
    Name = "lookddak-prod-v2-alb"
  })
}

resource "aws_lb_target_group" "nextjs" {
  name             = "lookddak-prod-v2-nextjs-tg"
  port             = 3000
  protocol         = "HTTP"
  protocol_version = "HTTP1"
  target_type      = "ip"
  vpc_id           = var.vpc_id

  # Default 300s made ECS rollouts wait ~5 min per deploy.
  deregistration_delay = 60

  health_check {
    enabled             = true
    path                = "/onboarding"
    port                = "traffic-port"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = merge(local.common_tags, {
    Name    = "lookddak-prod-v2-nextjs-tg"
    Service = "nextjs"
  })
}

resource "aws_lb_target_group" "spring" {
  name             = "lookddak-prod-v2-spring-tg"
  port             = 8080
  protocol         = "HTTP"
  protocol_version = "HTTP1"
  target_type      = "ip"
  vpc_id           = var.vpc_id

  # Default 300s made ECS rollouts wait ~5 min per deploy.
  deregistration_delay = 60

  health_check {
    enabled             = true
    path                = "/actuator/health"
    port                = "traffic-port"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = merge(local.common_tags, {
    Name    = "lookddak-prod-v2-spring-tg"
    Service = "spring"
  })
}

resource "aws_lb_target_group" "spring_sse" {
  name             = "lookddak-prod-v2-spring-sse-tg"
  port             = 8081
  protocol         = "HTTP"
  protocol_version = "HTTP1"
  target_type      = "ip"
  vpc_id           = var.vpc_id

  # SSE 연결은 계속 열려 있어 기본값(300초)이면 배포 때 이전 Task를 내리기까지 5분을 기다린다.
  # API Target Group과 같은 60초로 맞춘다. 끊긴 알림 스트림은 FE가 3초 뒤 새 Task로 재연결한다.
  deregistration_delay = 60

  health_check {
    enabled             = true
    path                = "/actuator/health"
    port                = "traffic-port"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = merge(local.common_tags, {
    Name    = "lookddak-prod-v2-spring-sse-tg"
    Service = "spring-sse"
  })
}

resource "aws_lb_target_group" "fastapi" {
  name             = "lookddak-prod-v2-fastapi-tg"
  port             = 8000
  protocol         = "HTTP"
  protocol_version = "HTTP1"
  target_type      = "ip"
  vpc_id           = var.vpc_id

  # Default 300s made ECS rollouts wait ~5 min per deploy.
  deregistration_delay = 60

  health_check {
    enabled             = true
    path                = "/health"
    port                = "traffic-port"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = merge(local.common_tags, {
    Name    = "lookddak-prod-v2-fastapi-tg"
    Service = "fastapi"
  })
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }

  tags = merge(local.common_tags, {
    Name = "lookddak-prod-v2-http"
  })
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate_validation.origin.certificate_arn

  # CloudFront must finish propagating the origin verification header before
  # the ALB starts rejecting requests that do not contain it.
  depends_on = [aws_cloudfront_distribution.this]

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "Forbidden"
      status_code  = "403"
    }
  }

  tags = merge(local.common_tags, {
    Name = "lookddak-prod-v2-https"
  })
}

# Runware webhook -> FastAPI. Priority 5 makes this more specific route win over /api/* -> Spring (10).
# The token is stored in SSM, but using it as an ALB condition also records it in Terraform state and ELB settings.
resource "aws_lb_listener_rule" "fastapi_webhook" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 5

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.fastapi.arn
  }

  condition {
    path_pattern {
      values = ["/api/v2/webhooks/runware"]
    }
  }

  condition {
    query_string {
      key   = "token"
      value = var.fastapi_webhook_token
    }
  }

  condition {
    http_header {
      http_header_name = "X-Lookddak-Origin-Verify"
      values           = [random_password.origin_verify.result]
    }
  }

  # CloudFront가 viewer Host를 전달하지 않으므로 ALB에는 origin 도메인만 도착한다.
  condition {
    host_header {
      values = [var.origin_domain_name]
    }
  }

  tags = merge(local.common_tags, {
    Name    = "lookddak-prod-v2-fastapi-webhook"
    Service = "fastapi"
  })
}

resource "aws_lb_listener_rule" "spring" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.spring.arn
  }

  condition {
    path_pattern {
      values = ["/api", "/api/*"]
    }
  }

  condition {
    http_header {
      http_header_name = "X-Lookddak-Origin-Verify"
      values           = [random_password.origin_verify.result]
    }
  }

  tags = merge(local.common_tags, {
    Name = "lookddak-prod-v2-spring"
  })
}

# Notification SSE uses a dedicated Spring port so only this long-lived route
# disables the Service Connect per-request timeout.
resource "aws_lb_listener_rule" "spring_sse" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 6

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.spring_sse.arn
  }

  condition {
    path_pattern {
      values = ["/api/v1/notifications/stream"]
    }
  }

  condition {
    http_header {
      http_header_name = "X-Lookddak-Origin-Verify"
      values           = [random_password.origin_verify.result]
    }
  }

  tags = merge(local.common_tags, {
    Name    = "lookddak-prod-v2-spring-sse"
    Service = "spring-sse"
  })
}

resource "aws_lb_listener_rule" "nextjs" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.nextjs.arn
  }

  condition {
    http_header {
      http_header_name = "X-Lookddak-Origin-Verify"
      values           = [random_password.origin_verify.result]
    }
  }

  tags = merge(local.common_tags, {
    Name = "lookddak-prod-v2-nextjs"
  })
}

resource "aws_route53_record" "origin" {
  zone_id = var.route53_zone_id
  name    = var.origin_domain_name
  type    = "A"

  alias {
    name                   = aws_lb.this.dns_name
    zone_id                = aws_lb.this.zone_id
    evaluate_target_health = false
  }
}

# -----------------------------------------------------------------------------
# Global certificate (CloudFront viewer)
# - lookddak.com, www.lookddak.com (v2-prod.lookddak.com validation hostname removed 2026-10-26)
# -----------------------------------------------------------------------------
resource "aws_acm_certificate" "viewer" {
  provider = aws.us_east_1

  domain_name               = var.production_domain_name
  subject_alternative_names = [var.production_www_domain_name]
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(local.common_tags, {
    Name = "lookddak-prod-v2-cloudfront"
  })
}

resource "aws_route53_record" "viewer_certificate_validation" {
  for_each = {
    for option in aws_acm_certificate.viewer.domain_validation_options :
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
}

resource "aws_acm_certificate_validation" "viewer" {
  provider = aws.us_east_1

  certificate_arn         = aws_acm_certificate.viewer.arn
  validation_record_fqdns = [for record in aws_route53_record.viewer_certificate_validation : record.fqdn]
}

resource "aws_cloudfront_distribution" "this" {
  enabled         = true
  is_ipv6_enabled = true
  http_version    = "http2and3"
  price_class     = "PriceClass_200"
  web_acl_id      = aws_wafv2_web_acl.this.arn
  aliases = [
    var.production_domain_name,
    var.production_www_domain_name,
  ]

  origin {
    domain_name = var.origin_domain_name
    origin_id   = "lookddak-prod-v2-alb"

    custom_header {
      name  = "X-Lookddak-Origin-Verify"
      value = random_password.origin_verify.result
    }

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
      origin_read_timeout    = 120
    }
  }

  default_cache_behavior {
    target_origin_id       = "lookddak-prod-v2-alb"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods         = ["GET", "HEAD", "OPTIONS"]
    compress               = true

    cache_policy_id          = data.aws_cloudfront_cache_policy.caching_disabled.id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_viewer_except_host.id
  }

  ordered_cache_behavior {
    path_pattern           = "/api"
    target_origin_id       = "lookddak-prod-v2-alb"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods         = ["GET", "HEAD", "OPTIONS"]
    compress               = true

    cache_policy_id          = data.aws_cloudfront_cache_policy.caching_disabled.id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_viewer_except_host.id
  }

  ordered_cache_behavior {
    path_pattern           = "/api/*"
    target_origin_id       = "lookddak-prod-v2-alb"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods         = ["GET", "HEAD", "OPTIONS"]
    compress               = true

    cache_policy_id          = data.aws_cloudfront_cache_policy.caching_disabled.id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_viewer_except_host.id
  }

  ordered_cache_behavior {
    path_pattern           = "/_next/static/*"
    target_origin_id       = "lookddak-prod-v2-alb"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD", "OPTIONS"]
    compress               = true

    cache_policy_id = data.aws_cloudfront_cache_policy.caching_optimized.id
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.viewer.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  depends_on = [
    aws_acm_certificate_validation.origin,
    aws_route53_record.origin,
  ]

  tags = merge(local.common_tags, {
    Name = "lookddak-prod-v2"
  })
}
