output "alb_arn" {
  description = "V2 dev Application Load Balancer ARN"
  value       = aws_lb.dev_v2.arn
}

output "alb_dns_name" {
  description = "V2 dev Application Load Balancer DNS name"
  value       = aws_lb.dev_v2.dns_name
}

output "alb_zone_id" {
  description = "V2 dev Application Load Balancer canonical hosted zone ID"
  value       = aws_lb.dev_v2.zone_id
}

output "test_domain_name" {
  description = "V2 dev test domain routed to the Application Load Balancer"
  value       = aws_route53_record.dev_v2.fqdn
}

output "https_listener_arn" {
  description = "V2 dev HTTPS listener ARN"
  value       = aws_lb_listener.https.arn
}

output "certificate_arn" {
  description = "ACM certificate ARN used by the V2 dev HTTPS listener"
  value       = aws_acm_certificate_validation.dev.certificate_arn
}

output "target_group_arns" {
  description = "V2 dev target group ARNs for future ECS services"
  value = merge(
    {
      nextjs = aws_lb_target_group.nextjs.arn
      spring = aws_lb_target_group.spring.arn
    },
    var.fastapi_enabled ? { fastapi = aws_lb_target_group.fastapi[0].arn } : {},
  )
}

output "v1_target_group_arn" {
  description = "V1 dev EC2 nginx target group ARN"
  value       = aws_lb_target_group.v1.arn
}
