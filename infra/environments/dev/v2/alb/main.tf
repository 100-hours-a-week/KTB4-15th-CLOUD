# ---------------------------------------------------------------
# ACM certificate
# - The service A alias remains owned by V1 until ECS services are ready.
# - This module creates only the DNS validation CNAME record.
# ---------------------------------------------------------------
resource "aws_acm_certificate" "dev" {
  domain_name       = var.domain_name
  validation_method = "DNS"

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

  tags = {
    Name        = "lookddak-dev-v2-alb"
    Environment = "dev"
    Version     = "v2"
  }
}

# ---------------------------------------------------------------
# Target groups
# - ECS services will register Fargate task IPs in a later step.
# - Custom health check settings are intentionally omitted.
# ---------------------------------------------------------------
resource "aws_lb_target_group" "nextjs" {
  name             = "lookddak-dev-v2-nextjs-tg"
  port             = 3000
  protocol         = "HTTP"
  protocol_version = "HTTP1"
  target_type      = "ip"
  vpc_id           = var.vpc_id

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

  tags = {
    Name        = "lookddak-dev-v2-spring-tg"
    Environment = "dev"
    Version     = "v2"
    Service     = "spring"
  }
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
# Path routing
# - The Spring rule must be evaluated before the broader Next.js rule.
# - ALB forwards the original /v2 path; application path handling is
#   finalized with the ECS task definitions and application configuration.
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
      values = ["/v2/api", "/v2/api/*"]
    }
  }

  tags = {
    Name        = "lookddak-dev-v2-spring"
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
    path_pattern {
      values = ["/v2", "/v2/*"]
    }
  }

  tags = {
    Name        = "lookddak-dev-v2-nextjs"
    Environment = "dev"
    Version     = "v2"
  }
}
