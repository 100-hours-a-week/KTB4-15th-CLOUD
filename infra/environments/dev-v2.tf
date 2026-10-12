# ---------------------------------------------------------------
# V2 dev (migration rehearsal / staging)
# - Reuse only the VPC and existing Public 2a subnet from V1 dev.
# - Keep every new V2 resource in dev/v2 to avoid V1 file conflicts.
# ---------------------------------------------------------------
module "dev_v2_network" {
  source = "./dev/v2/network"

  vpc_id                      = module.dev_v1_network.vpc_id
  existing_public_subnet_id   = module.dev_v1_network.public_subnet_ids[0]
  dev_mysql_security_group_id = module.dev_v1_network.db_security_group_id
}

module "dev_v2_alb" {
  source = "./dev/v2/alb"

  vpc_id                = module.dev_v1_network.vpc_id
  public_subnet_ids     = module.dev_v2_network.alb_public_subnet_ids
  alb_security_group_id = module.dev_v2_network.security_group_ids["alb"]
  route53_zone_id       = module.shared_core.route53_zone_id
  domain_name           = "dev.lookddak.com"
}

module "dev_v2_ecs_cluster" {
  source = "./dev/v2/ecs-cluster"
}

module "dev_v2_iam" {
  source = "./dev/v2/iam"

  ecs_cluster_arn = module.dev_v2_ecs_cluster.cluster_arn
}

module "dev_v2_database" {
  source = "./dev/v2/database"

  db_subnet_ids                = module.dev_v1_network.db_subnet_ids
  postgresql_security_group_id = module.dev_v2_network.security_group_ids["postgresql"]

  read_admin_password_from_ssm = var.dev_v2_postgresql_read_admin_password_from_ssm
  admin_password_wo            = var.dev_v2_postgresql_admin_password_wo
}

# The default path reads the manually-created SecureString with an ephemeral
# resource. The write-only input exists only so a full local plan can be run
# before that SecureString is created; it must not be used for apply.
variable "dev_v2_postgresql_read_admin_password_from_ssm" {
  description = "Read the V2 PostgreSQL admin password from the manually-created SSM SecureString"
  type        = bool
  default     = true
}

variable "dev_v2_postgresql_admin_password_wo" {
  description = "Plan-only write-only password input used when SSM lookup is disabled"
  type        = string
  default     = null
  sensitive   = true
  ephemeral   = true
}
