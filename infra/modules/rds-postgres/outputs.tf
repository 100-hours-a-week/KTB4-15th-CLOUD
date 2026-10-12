output "address" {
  description = "RDS PostgreSQL endpoint address"
  value       = aws_db_instance.this.address
}

output "port" {
  description = "RDS PostgreSQL port"
  value       = aws_db_instance.this.port
}

output "db_name" {
  description = "Initial PostgreSQL database name"
  value       = aws_db_instance.this.db_name
}

output "master_username" {
  description = "PostgreSQL administrator username"
  value       = aws_db_instance.this.username
}

output "arn" {
  description = "RDS PostgreSQL instance ARN"
  value       = aws_db_instance.this.arn
}

output "identifier" {
  description = "RDS PostgreSQL instance identifier"
  value       = aws_db_instance.this.identifier
}

output "parameter_group_name" {
  description = "Custom PostgreSQL parameter group name"
  value       = aws_db_parameter_group.this.name
}

output "subnet_group_name" {
  description = "PostgreSQL DB subnet group name"
  value       = aws_db_subnet_group.this.name
}
