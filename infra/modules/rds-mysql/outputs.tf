output "address" {
  description = "RDS 엔드포인트 주소"
  value       = aws_db_instance.this.address
}

output "port" {
  description = "RDS 포트"
  value       = aws_db_instance.this.port
}

output "db_name" {
  description = "초기 데이터베이스 이름"
  value       = aws_db_instance.this.db_name
}

output "master_username" {
  description = "마스터 사용자 이름"
  value       = aws_db_instance.this.username
}

output "arn" {
  description = "RDS 인스턴스 ARN"
  value       = aws_db_instance.this.arn
}

output "identifier" {
  description = "RDS 인스턴스 identifier"
  value       = aws_db_instance.this.identifier
}
