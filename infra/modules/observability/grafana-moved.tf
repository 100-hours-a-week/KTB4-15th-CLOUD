moved {
  from = aws_acm_certificate.grafana
  to   = aws_acm_certificate.grafana[0]
}

moved {
  from = aws_acm_certificate_validation.grafana
  to   = aws_acm_certificate_validation.grafana[0]
}

moved {
  from = aws_lb_listener_certificate.grafana
  to   = aws_lb_listener_certificate.grafana[0]
}

moved {
  from = aws_lb_target_group.grafana
  to   = aws_lb_target_group.grafana[0]
}

moved {
  from = aws_lb_target_group_attachment.grafana
  to   = aws_lb_target_group_attachment.grafana[0]
}

moved {
  from = aws_vpc_security_group_egress_rule.alb_to_grafana
  to   = aws_vpc_security_group_egress_rule.alb_to_grafana[0]
}

moved {
  from = aws_vpc_security_group_ingress_rule.grafana_from_alb
  to   = aws_vpc_security_group_ingress_rule.grafana_from_alb[0]
}

moved {
  from = aws_lb_listener_rule.grafana
  to   = aws_lb_listener_rule.grafana[0]
}

moved {
  from = aws_vpc_security_group_egress_rule.alb_to_cognito
  to   = aws_vpc_security_group_egress_rule.alb_to_cognito[0]
}

moved {
  from = aws_iam_role.grafana_logout
  to   = aws_iam_role.grafana_logout[0]
}

moved {
  from = aws_iam_role_policy_attachment.grafana_logout_basic
  to   = aws_iam_role_policy_attachment.grafana_logout_basic[0]
}

moved {
  from = aws_cloudwatch_log_group.grafana_logout
  to   = aws_cloudwatch_log_group.grafana_logout[0]
}

moved {
  from = aws_lambda_function.grafana_logout
  to   = aws_lambda_function.grafana_logout[0]
}

moved {
  from = aws_lb_target_group.grafana_logout
  to   = aws_lb_target_group.grafana_logout[0]
}

moved {
  from = aws_lambda_permission.grafana_logout_alb
  to   = aws_lambda_permission.grafana_logout_alb[0]
}

moved {
  from = aws_lb_target_group_attachment.grafana_logout
  to   = aws_lb_target_group_attachment.grafana_logout[0]
}

moved {
  from = aws_lb_listener_rule.grafana_logout
  to   = aws_lb_listener_rule.grafana_logout[0]
}
