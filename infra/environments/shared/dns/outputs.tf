output "zone_id" {
  description = "lookddak.com Hosted Zone ID"
  value       = aws_route53_zone.main.zone_id
}

output "name_servers" {
  description = "lookddak.com Hosted Zone name servers"
  value       = aws_route53_zone.main.name_servers
}

output "dev_domain" {
  description = "Single Dev domain"
  value       = aws_route53_record.dev.fqdn
}
