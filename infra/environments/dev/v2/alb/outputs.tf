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
  value = {
    nextjs = aws_lb_target_group.nextjs.arn
    spring = aws_lb_target_group.spring.arn
  }
}
