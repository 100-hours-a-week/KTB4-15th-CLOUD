# ---------------------------------------------------------------
# ACM certificate
# - dev.lookddak.com and v2-dev.lookddak.com both terminate TLS on this ALB.
# ---------------------------------------------------------------
resource "aws_acm_certificate" "dev" {
  domain_name               = var.domain_name
  subject_alternative_names = var.subject_alternative_names
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name        = "lookddak-dev-v2"
    Environment = "dev"
    Version     = "v2"
  }
}

resource "aws_route53_record" "certificate_validation" {
  for_each = {
    for option in aws_acm_certificate.dev.domain_validation_options :
    option.domain_name => {
      name   = option.resource_record_name
      record = option.resource_record_value
      type   = option.resource_record_type
    }
  }

  zone_id = var.route53_zone_id
  name    = each.value.name
  type    = each.value.type
  ttl     = 300
  records = [each.value.record]
}

resource "aws_acm_certificate_validation" "dev" {
  certificate_arn         = aws_acm_certificate.dev.arn
  validation_record_fqdns = [for record in aws_route53_record.certificate_validation : record.fqdn]
}

resource "aws_route53_record" "dev_v2" {
  zone_id = var.route53_zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_lb.dev_v2.dns_name
    zone_id                = aws_lb.dev_v2.zone_id
    evaluate_target_health = false
  }
}

# ---------------------------------------------------------------
# Application Load Balancer
# ---------------------------------------------------------------
resource "aws_lb" "dev_v2" {
  name               = "lookddak-dev-v2-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.alb_security_group_id]
  subnets            = var.public_subnet_ids
  ip_address_type    = "ipv4"

  # 액세스 로그 → S3 (5분마다 파일). 버킷은 observability 모듈이 만든다.
  dynamic "access_logs" {
    for_each = var.access_logs_bucket == null ? [] : [var.access_logs_bucket]

    content {
      bucket  = access_logs.value
      prefix  = "alb"
      enabled = true
    }
  }

  tags = {
    Name        = "lookddak-dev-v2-alb"
    Environment = "dev"
    Version     = "v2"
  }
}

# ---------------------------------------------------------------
# Target groups
# - ECS services will register Fargate task IPs in a later step.
# ---------------------------------------------------------------
resource "aws_lb_target_group" "nextjs" {
  name             = "lookddak-dev-v2-nextjs-tg"
  port             = 3000
  protocol         = "HTTP"
  protocol_version = "HTTP1"
  target_type      = "ip"
  vpc_id           = var.vpc_id

  # Default 300s made ECS rollouts wait ~5 min per deploy.
  deregistration_delay = 30

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

  tags = {
    Name        = "lookddak-dev-v2-nextjs-tg"
    Environment = "dev"
    Version     = "v2"
    Service     = "nextjs"
  }
}

resource "aws_lb_target_group" "spring" {
  name             = "lookddak-dev-v2-spring-tg"
  port             = 8080
  protocol         = "HTTP"
  protocol_version = "HTTP1"
  target_type      = "ip"
  vpc_id           = var.vpc_id

  # Default 300s made ECS rollouts wait ~5 min per deploy.
  deregistration_delay = 30

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

  tags = {
    Name        = "lookddak-dev-v2-spring-tg"
    Environment = "dev"
    Version     = "v2"
    Service     = "spring"
  }
}

resource "aws_lb_target_group" "spring_sse" {
  name             = "lookddak-dev-v2-spring-sse-tg"
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

  tags = {
    Name        = "lookddak-dev-v2-spring-sse-tg"
    Environment = "dev"
    Version     = "v2"
    Service     = "spring-sse"
  }
}

# FastAPI (temporary, var.fastapi_enabled)
# - /api/v2/* is forwarded as-is (no path rewrite).
resource "aws_lb_target_group" "fastapi" {
  count = var.fastapi_enabled ? 1 : 0

  name             = "lookddak-dev-v2-fastapi-tg"
  port             = 8000
  protocol         = "HTTP"
  protocol_version = "HTTP1"
  target_type      = "ip"
  vpc_id           = var.vpc_id

  # Default 300s made ECS rollouts wait ~5 min per deploy.
  deregistration_delay = 30

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

  tags = {
    Name        = "lookddak-dev-v2-fastapi-tg"
    Environment = "dev"
    Version     = "v2"
    Service     = "fastapi"
  }
}

# V1 dev EC2 nginx
# - HTTPS to nginx so the existing nginx HTTP->HTTPS redirect is not hit.
# - ALB does not validate the backend certificate, so the V1 Let's Encrypt
#   certificate only encrypts ALB -> nginx. Users see the ACM certificate.
resource "aws_lb_target_group" "v1" {
  name             = "lookddak-dev-v1-tg"
  port             = 443
  protocol         = "HTTPS"
  protocol_version = "HTTP1"
  target_type      = "instance"
  vpc_id           = var.vpc_id

  health_check {
    enabled             = true
    path                = var.v1_health_check_path
    port                = "traffic-port"
    protocol            = "HTTPS"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = {
    Name        = "lookddak-dev-v1-tg"
    Environment = "dev"
    Version     = "v1"
  }
}

resource "aws_lb_target_group_attachment" "v1" {
  target_group_arn = aws_lb_target_group.v1.arn
  target_id        = var.v1_instance_id
  port             = 443
}

# ---------------------------------------------------------------
# Listeners
# ---------------------------------------------------------------
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.dev_v2.arn
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

  tags = {
    Name        = "lookddak-dev-v2-http"
    Environment = "dev"
    Version     = "v2"
  }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.dev_v2.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate_validation.dev.certificate_arn

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "Not Found"
      status_code  = "404"
    }
  }

  tags = {
    Name        = "lookddak-dev-v2-https"
    Environment = "dev"
    Version     = "v2"
  }
}

# ---------------------------------------------------------------
# Host and path routing
# - The Spring rule must be evaluated before the broader Next.js rule.
# - No /v2 prefix is forwarded to either application.
# ---------------------------------------------------------------
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
    host_header {
      values = [
        var.domain_name,
        var.v1_domain_name,
      ]
    }
  }

  tags = {
    Name        = "lookddak-dev-v2-spring"
    Environment = "dev"
    Version     = "v2"
  }
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
    host_header {
      values = [
        var.domain_name,
        var.v1_domain_name,
      ]
    }
  }

  tags = {
    Name        = "lookddak-dev-v2-spring-sse"
    Environment = "dev"
    Version     = "v2"
  }
}

# Temporary: Runware webhook -> FastAPI. Priority 5 so it wins over the Spring /api/* rule (10).
# - Only /api/v2/webhooks/runware with ?token=<SSM /lookddak/dev/fastapi/webhook-token> is forwarded.
#   Anything else falls through to the Spring /api/* rule (404 there).
# - The token is a rule condition, so it is stored in plain text in Terraform state,
#   the ELB console, and CloudTrail (CreateRule/ModifyRule). Plan output hides it (sensitive).
# - ALB matches query values case-insensitively and treats * and ? as wildcards;
#   the token must be URL-safe [A-Za-z0-9_-]. Rotating the token requires a new apply.
resource "aws_lb_listener_rule" "fastapi" {
  count = var.fastapi_enabled ? 1 : 0

  listener_arn = aws_lb_listener.https.arn
  priority     = 5

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.fastapi[0].arn
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
        var.domain_name,
        var.v1_domain_name,
      ]
    }
  }

  tags = {
    Name        = "lookddak-dev-v2-fastapi"
    Environment = "dev"
    Version     = "v2"
  }
}

resource "aws_lb_listener_rule" "nextjs" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 20

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.nextjs.arn
  }

  condition {
    host_header {
      values = [
        var.domain_name,
        var.v1_domain_name,
      ]
    }
  }

  tags = {
    Name        = "lookddak-dev-v2-nextjs"
    Environment = "dev"
    Version     = "v2"
  }
}

# V1 fallback is kept temporarily for rollback.
# The higher-priority V2 rules now match dev.lookddak.com first, so this rule
# receives no normal traffic after the cutover.
resource "aws_lb_listener_rule" "v1" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 30

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.v1.arn
  }

  condition {
    host_header {
      values = [var.v1_domain_name]
    }
  }

  tags = {
    Name        = "lookddak-dev-v1"
    Environment = "dev"
    Version     = "v1"
  }
}
