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
  dev_app_security_group_id   = module.dev_v1_network.app_security_group_id
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

module "dev_v2_logging" {
  source = "./dev/v2/logging"
}

module "dev_v2_sqs" {
  source = "./dev/v2/sqs"
}

module "dev_v2_iam" {
  source = "./dev/v2/iam"

  ecs_cluster_arn = module.dev_v2_ecs_cluster.cluster_arn
  log_group_arns  = values(module.dev_v2_logging.log_group_arns)
  sqs_queue_arns  = module.dev_v2_sqs.queue_arns
}

module "dev_v2_database" {
  source = "./dev/v2/database"

  db_subnet_ids                = module.dev_v1_network.db_subnet_ids
  postgresql_security_group_id = module.dev_v2_network.security_group_ids["postgresql"]
  mysql_security_group_id      = module.dev_v2_network.security_group_ids["mysql"]
  v1_mysql_identifier          = module.dev_v1_database.mysql_identifier

  read_admin_password_from_ssm = var.dev_v2_postgresql_read_admin_password_from_ssm
  admin_password_wo            = var.dev_v2_postgresql_admin_password_wo
}

module "dev_v2_crawler" {
  source = "./dev/v2/crawler"

  ecs_cluster_arn           = module.dev_v2_ecs_cluster.cluster_arn
  scheduler_role_arn        = module.dev_v2_iam.crawler_scheduler_role_arn
  private_app_subnet_ids    = module.dev_v2_network.private_app_subnet_ids
  crawler_security_group_id = module.dev_v2_network.security_group_ids["crawler"]
}

module "dev_v2_ecs_services" {
  source = "./dev/v2/ecs-services"

  create_services        = var.dev_v2_create_services
  cluster_arn            = module.dev_v2_ecs_cluster.cluster_arn
  cluster_name           = module.dev_v2_ecs_cluster.cluster_name
  private_app_subnet_ids = module.dev_v2_network.private_app_subnet_ids
  security_group_ids     = module.dev_v2_network.security_group_ids
  target_group_arns      = module.dev_v2_alb.target_group_arns
  task_definition_arns   = var.dev_v2_task_definition_arns
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

variable "dev_v2_create_services" {
  description = "Create the V2 dev ECS services and their Auto Scaling resources"
  type        = bool
  default     = false
}

variable "dev_v2_task_definition_arns" {
  description = "Initial registered V2 task definition revision ARNs keyed by nextjs, spring, and fastapi"
  type        = map(string)
  default     = {}
}

output "dev_fastapi_body_image_validation_parameter_paths" {
  description = "SecureString paths to create manually for the shared V1/V2 dev FastAPI body image validation integration"
  value       = module.dev_parameter_store.fastapi_body_image_validation_parameter_paths
}

output "dev_v2_sqs_queue_urls" {
  description = "V2 dev fitting main queue URLs for Spring and FastAPI task definitions"
  value       = module.dev_v2_sqs.queue_urls
}

output "dev_v2_sqs_queue_arns" {
  description = "V2 dev fitting main queue ARNs"
  value       = module.dev_v2_sqs.queue_arns
}

output "dev_v2_sqs_dlq_urls" {
  description = "V2 dev fitting dead-letter queue URLs"
  value       = module.dev_v2_sqs.dlq_urls
}

output "dev_v2_sqs_dlq_arns" {
  description = "V2 dev fitting dead-letter queue ARNs"
  value       = module.dev_v2_sqs.dlq_arns
}

output "dev_v2_sqs_alarm_names" {
  description = "V2 dev fitting SQS CloudWatch alarm names routed through the existing Discord alert pipeline"
  value       = module.dev_v2_sqs.alarm_names
}

output "dev_v2_sqs_task_role_arns" {
  description = "V2 dev Spring and FastAPI task roles with fitting queue permissions"
  value = {
    spring  = module.dev_v2_iam.task_role_arns["spring"]
    fastapi = module.dev_v2_iam.task_role_arns["fastapi"]
  }
}

output "dev_v2_log_group_names" {
  description = "V2 dev ECS application CloudWatch Log Group names"
  value       = module.dev_v2_logging.log_group_names
}

output "dev_v2_runtime_secure_parameter_arns" {
  description = "V2 PostgreSQL SecureString ARNs managed manually outside Terraform"
  value       = module.dev_v2_database.secure_parameter_arns
}
