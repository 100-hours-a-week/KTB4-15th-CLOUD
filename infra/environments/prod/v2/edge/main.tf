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

  health_check {
    enabled             = true
    path                = "/onboarding"
    port                = "traffic-port"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
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

  health_check {
    enabled             = true
    path                = "/health"
    port                = "traffic-port"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
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

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.nextjs.arn
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
    host_header {
      values = [
        var.origin_domain_name,
        var.test_domain_name,
        var.production_domain_name,
      ]
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

  tags = merge(local.common_tags, {
    Name    = "lookddak-prod-v2-spring-sse"
    Service = "spring-sse"
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
# Global certificate and CloudFront validation hostname
# - lookddak.com is covered now, but its current DNS record remains untouched.
# -----------------------------------------------------------------------------
resource "aws_acm_certificate" "viewer" {
  provider = aws.us_east_1

  domain_name               = var.test_domain_name
  subject_alternative_names = [var.production_domain_name]
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
  aliases = [
    var.test_domain_name,
    var.production_domain_name,
  ]

  origin {
    domain_name = var.origin_domain_name
    origin_id   = "lookddak-prod-v2-alb"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
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

resource "aws_route53_record" "test_domain_ipv4" {
  zone_id = var.route53_zone_id
  name    = var.test_domain_name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.this.domain_name
    zone_id                = aws_cloudfront_distribution.this.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "test_domain_ipv6" {
  zone_id = var.route53_zone_id
  name    = var.test_domain_name
  type    = "AAAA"

  alias {
    name                   = aws_cloudfront_distribution.this.domain_name
    zone_id                = aws_cloudfront_distribution.this.hosted_zone_id
    evaluate_target_health = false
  }
}
