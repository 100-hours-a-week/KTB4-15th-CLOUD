output "postgresql_backup_bucket_arn" {
  description = "운영 PostgreSQL 백업 버킷 ARN"
  value       = aws_s3_bucket.postgresql_backup.arn
}

output "postgresql_backup_bucket_name" {
  description = "운영 PostgreSQL 백업 버킷 이름"
  value       = aws_s3_bucket.postgresql_backup.id
}

output "postgresql_backup_kms_key_arn" {
  description = "운영 PostgreSQL 백업 암호화 KMS 키 ARN"
  value       = aws_kms_key.postgresql_backup.arn
}
