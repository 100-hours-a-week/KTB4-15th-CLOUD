output "vpc_id" {
  description = "LookDDak prod VPC ID"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "Public 서브넷 ID 목록"
  value       = [aws_subnet.public_a.id]
}

output "db_subnet_ids" {
  description = "DB 서브넷 ID 목록"
  value       = [aws_subnet.private_db_a.id, aws_subnet.private_db_c.id]
}

output "app_security_group_id" {
  description = "EC2 애플리케이션 보안그룹 ID"
  value       = aws_security_group.app.id
}

output "db_security_group_id" {
  description = "RDS 보안그룹 ID"
  value       = aws_security_group.db.id
}

output "crawler_security_group_id" {
  description = "크롤러 보안그룹 ID"
  value       = aws_security_group.crawler.id
}
