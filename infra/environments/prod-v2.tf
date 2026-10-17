# ---------------------------------------------------------------
# V2 prod network foundation
# - Reuse the V1 prod VPC, existing Public 2a subnet, and Internet Gateway.
# - Create only the additional subnets, NAT Gateway, and routing required by V2.
# ---------------------------------------------------------------
module "prod_v2_network" {
  source = "./prod/v2/network"

  vpc_id                     = module.prod_v1_network.vpc_id
  existing_public_subnet_id  = module.prod_v1_network.public_subnet_ids[0]
  prod_app_security_group_id = module.prod_v1_network.app_security_group_id
}

module "prod_v2_database" {
  source = "./prod/v2/database"

  db_subnet_ids                = module.prod_v1_network.db_subnet_ids
  postgresql_security_group_id = module.prod_v2_network.security_group_ids["postgresql"]

  read_admin_password_from_ssm = var.prod_v2_postgresql_read_admin_password_from_ssm
  admin_password_wo            = var.prod_v2_postgresql_admin_password_wo
}

# The default path reads the manually-created SecureString with an ephemeral
# resource. The write-only input exists only so a full local plan can be run
# before that SecureString is created; it must not be used for apply.
variable "prod_v2_postgresql_read_admin_password_from_ssm" {
  description = "Read the V2 Prod PostgreSQL admin password from the manually-created SSM SecureString"
  type        = bool
  default     = true
}

variable "prod_v2_postgresql_admin_password_wo" {
  description = "Plan-only write-only password input used when SSM lookup is disabled"
  type        = string
  default     = null
  sensitive   = true
  ephemeral   = true
}

output "prod_v2_postgresql_parameter_paths" {
  description = "Parameter Store paths used by V2 Prod PostgreSQL"
  value       = module.prod_v2_database.parameter_paths
}

output "prod_v2_postgresql_secure_parameter_arns" {
  description = "V2 Prod PostgreSQL SecureString ARNs managed manually outside Terraform"
  value       = module.prod_v2_database.secure_parameter_arns
}
