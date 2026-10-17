output "s3_key" {
  description = "템플릿 객체 키"
  value       = aws_s3_object.this.key
}

output "s3_version_id" {
  description = "템플릿 객체 버전 ID (배포 기록에 남김)"
  value       = aws_s3_object.this.version_id
}

output "family" {
  description = "Task Definition family"
  value       = var.family
}
