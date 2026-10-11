output "app_security_group_id" {
  description = "dev EC2 애플리케이션 보안 그룹 ID"
  value       = aws_security_group.app.id
}

output "db_security_group_id" {
  description = "dev RDS 보안 그룹 ID"
  value       = aws_security_group.db.id
}
