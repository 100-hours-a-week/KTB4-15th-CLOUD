output "mysql_database_name" {
  description = "Name of the production MySQL database"
  value       = module.mysql.db_name
}

output "mysql_address" {
  description = "DNS address of the production MySQL instance"
  value       = module.mysql.address
}

output "mysql_port" {
  description = "Port of the production MySQL instance"
  value       = module.mysql.port
}

output "mysql_master_username" {
  description = "Master username of the production MySQL instance"
  value       = module.mysql.master_username
}
