output "vpc_id" {
  description = "dev VPC ID"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "dev public 서브넷 ID 목록"
  value       = [aws_subnet.public_a.id]
}

output "db_subnet_ids" {
  description = "dev DB 서브넷 ID 목록"
  value       = [aws_subnet.private_db_a.id, aws_subnet.private_db_c.id]
}

