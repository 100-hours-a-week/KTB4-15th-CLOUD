output "rds_arn" {
  description = "V2 Prod PostgreSQL RDS ARN"
  value       = module.postgresql.arn
}

output "rds_identifier" {
  description = "V2 Prod PostgreSQL RDS identifier"
  value       = module.postgresql.identifier
}

output "rds_address" {
  description = "V2 Prod PostgreSQL endpoint address"
  value       = module.postgresql.address
}

output "rds_port" {
  description = "V2 Prod PostgreSQL port"
  value       = module.postgresql.port
}

output "parameter_group_name" {
  description = "V2 Prod PostgreSQL custom parameter group name"
  value       = module.postgresql.parameter_group_name
}

output "parameter_paths" {
  description = "Parameter Store paths used by V2 Prod PostgreSQL"
  value       = local.parameter_paths
}

output "secure_parameter_arns" {
  description = "SecureString ARNs that must be created manually"
  value = {
    for name, path in local.secure_parameter_paths :
    name => "arn:aws:ssm:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:parameter${path}"
  }
}

output "mysql_identifier" {
  description = "V2 prod MySQL RDS identifier"
  value       = module.mysql.identifier
}

output "mysql_address" {
  description = "V2 prod MySQL endpoint address"
  value       = module.mysql.address
}
