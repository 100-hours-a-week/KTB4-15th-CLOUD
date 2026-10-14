output "mysql_address" {
  description = "DNS address of the dev MySQL instance"
  value       = module.mysql.address
}

output "mysql_port" {
  description = "Port of the dev MySQL instance"
  value       = module.mysql.port
}

output "mysql_database_name" {
  description = "Name of the dev MySQL database"
  value       = module.mysql.db_name
}

output "mysql_master_username" {
  description = "Master username of the dev MySQL instance"
  value       = module.mysql.master_username
}

output "mysql_identifier" {
  description = "Identifier of the dev MySQL instance"
  value       = module.mysql.identifier
}
