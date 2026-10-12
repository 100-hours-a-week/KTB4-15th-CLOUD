# Non-sensitive connection metadata is managed by Terraform.
# SecureString password parameters are intentionally not created here because
# Parameter Store does not support value-less parameters.
locals {
  string_parameters = {
    admin_username = {
      name        = local.parameter_paths.admin_username
      description = "LookDDak dev V2 PostgreSQL administrator username"
      value       = module.postgresql.master_username
      credential  = "admin"
    }
    host = {
      name        = local.parameter_paths.host
      description = "LookDDak dev V2 PostgreSQL endpoint"
      value       = module.postgresql.address
      credential  = "connection"
    }
    port = {
      name        = local.parameter_paths.port
      description = "LookDDak dev V2 PostgreSQL port"
      value       = tostring(module.postgresql.port)
      credential  = "connection"
    }
    database = {
      name        = local.parameter_paths.database
      description = "LookDDak dev V2 PostgreSQL database name"
      value       = module.postgresql.db_name
      credential  = "connection"
    }
    app_username = {
      name        = local.parameter_paths.app_username
      description = "LookDDak dev V2 PostgreSQL application username"
      value       = local.app_username
      credential  = "app"
    }
    migration_username = {
      name        = local.parameter_paths.migration_username
      description = "LookDDak dev V2 PostgreSQL migration username"
      value       = local.migration_username
      credential  = "migration"
    }
  }
}

resource "aws_ssm_parameter" "postgresql" {
  for_each = local.string_parameters

  name        = each.value.name
  description = each.value.description
  type        = "String"
  value       = each.value.value
  tier        = "Standard"
  data_type   = "text"

  tags = {
    CredentialType = each.value.credential
    Environment    = "dev"
    Service        = "postgresql"
    Version        = "v2"
  }
}
