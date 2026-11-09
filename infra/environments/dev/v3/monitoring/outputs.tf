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
