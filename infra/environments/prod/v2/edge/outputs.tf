output "alb_arn" {
  description = "V2 Prod Application Load Balancer ARN"
  value       = aws_lb.this.arn
}

output "alb_dns_name" {
  description = "V2 Prod Application Load Balancer DNS name"
  value       = aws_lb.this.dns_name
}

output "target_group_arns" {
  description = "V2 Prod target group ARNs keyed by service name"
  value = {
    nextjs     = aws_lb_target_group.nextjs.arn
    spring     = aws_lb_target_group.spring.arn
    spring_sse = aws_lb_target_group.spring_sse.arn
    fastapi    = aws_lb_target_group.fastapi.arn
  }
}

output "cloudfront_distribution_id" {
  description = "V2 Prod CloudFront distribution ID"
  value       = aws_cloudfront_distribution.this.id
}

output "cloudfront_domain_name" {
  description = "V2 Prod CloudFront distribution domain name"
  value       = aws_cloudfront_distribution.this.domain_name
}

output "test_domain_name" {
  description = "V2 Prod validation hostname routed to CloudFront"
  value       = aws_route53_record.test_domain_ipv4.fqdn
}

output "origin_domain_name" {
  description = "V2 Prod ALB origin hostname"
  value       = aws_route53_record.origin.fqdn
}
