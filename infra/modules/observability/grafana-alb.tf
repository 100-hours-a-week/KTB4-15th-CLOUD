# ---------------------------------------------------------------
# Grafana 외부 접속: grafana.dev.lookddak.com → dev V2 ALB → Monitoring EC2:3000
# - 인증서는 따로 만들어 HTTPS 리스너에 SNI로 추가한다 (기존 인증서 교체 없음).
# - 리스너 규칙(Cognito 인증 → Grafana 전달)은 grafana-cognito.tf에 있다.
# - Grafana 3000은 ALB 보안 그룹에서만 들어온다. Alloy 3500은 ALB에 연결하지 않는다.
# ---------------------------------------------------------------

# --- 인증서 ---
resource "aws_acm_certificate" "grafana" {
  domain_name       = var.grafana_domain_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(local.common_tags, {
    Name = "lookddak-${var.environment}-grafana"
  })
}

resource "aws_route53_record" "grafana_certificate_validation" {
  for_each = {
    for option in aws_acm_certificate.grafana.domain_validation_options :
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

resource "aws_acm_certificate_validation" "grafana" {
  certificate_arn         = aws_acm_certificate.grafana.arn
  validation_record_fqdns = [for record in aws_route53_record.grafana_certificate_validation : record.fqdn]
}

resource "aws_lb_listener_certificate" "grafana" {
  listener_arn    = var.https_listener_arn
  certificate_arn = aws_acm_certificate_validation.grafana.certificate_arn
}

# --- Target Group ---
resource "aws_lb_target_group" "grafana" {
  name        = "lookddak-${var.environment}-v2-grafana-tg"
  port        = 3000
  protocol    = "HTTP"
  target_type = "instance"
  vpc_id      = var.vpc_id

  health_check {
    path                = "/api/health"
    matcher             = "200"
    interval            = 30
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = merge(local.common_tags, {
    Name = "lookddak-${var.environment}-v2-grafana-tg"
  })
}

resource "aws_lb_target_group_attachment" "grafana" {
  target_group_arn = aws_lb_target_group.grafana.arn
  target_id        = aws_instance.this.id
  port             = 3000
}

# --- 보안 그룹: ALB → Grafana 3000 ---
resource "aws_vpc_security_group_egress_rule" "alb_to_grafana" {
  security_group_id            = var.alb_security_group_id
  description                  = "Grafana on the monitoring server"
  ip_protocol                  = "tcp"
  from_port                    = 3000
  to_port                      = 3000
  referenced_security_group_id = aws_security_group.this.id
}

resource "aws_vpc_security_group_ingress_rule" "grafana_from_alb" {
  security_group_id            = aws_security_group.this.id
  description                  = "Grafana from the ${var.environment} V2 ALB"
  ip_protocol                  = "tcp"
  from_port                    = 3000
  to_port                      = 3000
  referenced_security_group_id = var.alb_security_group_id
}

# --- DNS ---
resource "aws_route53_record" "grafana" {
  zone_id = var.route53_zone_id
  name    = var.grafana_domain_name
  type    = "A"

  alias {
    name                   = var.alb_dns_name
    zone_id                = var.alb_zone_id
    evaluate_target_health = false
  }
}
