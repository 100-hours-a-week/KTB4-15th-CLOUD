output "bucket_names" {
  description = "Loki·Tempo Helm values에 넣을 S3 버킷 이름"
  value       = { for k, b in aws_s3_bucket.this : k => b.id }
}

output "role_arns" {
  description = "monitoring Namespace ServiceAccount에 연결할 IRSA Role ARN"
  value       = { for k, r in aws_iam_role.this : k => r.arn }
}

output "db_log_tailer_repository_url" {
  description = "db-log-tailer 이미지 저장소 URL"
  value       = aws_ecr_repository.db_log_tailer.repository_url
}

output "mysql_exporter_bootstrap_command" {
  description = "V3 MySQL exporter 계정을 최초 1회 구성하는 명령"
  value       = "aws ssm send-command --region ${local.region} --instance-ids ${var.db_access_instance_id} --document-name ${aws_ssm_document.mysql_exporter_bootstrap.name} --comment 'Bootstrap LookDDak Dev V3 MySQL exporter' --query 'Command.CommandId' --output text"
}

output "grafana_cognito_client_id" {
  description = "oauth2-proxy에 넣을 Grafana Cognito App Client ID"
  value       = aws_cognito_user_pool_client.grafana.id
}

output "redis_readonly_acl_rule" {
  description = "Redis ACL user 규칙 (비밀번호는 SHA-256 해시)"
  value       = "user ${local.redis_readonly.username} on #${nonsensitive(sha256(random_password.redis_readonly.result))} ~* resetchannels -@all +@read +@connection +cluster|slots +cluster|shards +cluster|nodes +cluster|info -@dangerous +info"
}

