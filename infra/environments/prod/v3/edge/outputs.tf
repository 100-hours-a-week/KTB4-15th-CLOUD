output "cloudfront_distribution_id" {
  description = "Prod V3 공용 CloudFront Distribution ID"
  value       = aws_cloudfront_distribution.this.id
}

output "cloudfront_domain_name" {
  description = "Prod V3 공용 CloudFront 도메인"
  value       = aws_cloudfront_distribution.this.domain_name
}

output "argocd_url" {
  description = "Prod Argo CD 외부 URL"
  value       = "https://${var.domain_name}"
}

output "validation_urls" {
  description = "Prod V3 검증 도메인별 URL"
  value       = { for domain in var.additional_domain_names : domain => "https://${domain}" }
}

output "gateway_nlb_dns_name" {
  description = "GitOps Gateway가 생성한 Internal NLB DNS 이름"
  value       = data.aws_lb.gateway.dns_name
}

output "gateway_nlb_security_group_id" {
  description = "GitOps Gateway의 aws-load-balancer-security-groups annotation에 연결할 SG ID"
  value       = aws_security_group.gateway_nlb.id
}

output "web_acl_arn" {
  description = "Prod V3 Edge WAF Web ACL ARN"
  value       = aws_wafv2_web_acl.argocd.arn
}
