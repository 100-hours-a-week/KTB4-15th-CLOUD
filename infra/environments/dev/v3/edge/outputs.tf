output "gateway_nlb_security_group_id" {
  description = "GITOPS Gateway 어노테이션 aws-load-balancer-security-groups에 넣을 값"
  value       = aws_security_group.gateway_nlb.id
}

output "cloudfront_domain_name" {
  value = aws_cloudfront_distribution.this.domain_name
}

output "gateway_nlb_dns_name" {
  value = data.aws_lb.gateway.dns_name
}
