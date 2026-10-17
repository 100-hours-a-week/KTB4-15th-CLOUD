output "template_s3_keys" {
  description = "서비스별 템플릿 S3 키"
  value       = { for service, template in module.template : service => template.s3_key }
}

output "template_s3_version_ids" {
  description = "서비스별 템플릿 S3 객체 버전 ID"
  value       = { for service, template in module.template : service => template.s3_version_id }
}
