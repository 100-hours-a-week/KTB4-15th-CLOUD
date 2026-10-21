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
  fastapi_alb_enabled         = var.dev_v2_fastapi_alb_enabled
}

module "dev_v2_alb" {
  source = "./dev/v2/alb"

  vpc_id                = module.dev_v1_network.vpc_id
  public_subnet_ids     = module.dev_v2_network.alb_public_subnet_ids
  alb_security_group_id = module.dev_v2_network.security_group_ids["alb"]
  route53_zone_id       = module.shared_core.route53_zone_id
  domain_name           = "v2-dev.lookddak.com"
  subject_alternative_names = [
    "dev.lookddak.com",
  ]

  v1_domain_name       = "dev.lookddak.com"
  v1_instance_id       = module.dev_v1_compute.instance_id
  v1_health_check_path = var.dev_v1_alb_health_check_path

  fastapi_enabled       = var.dev_v2_fastapi_alb_enabled
  fastapi_webhook_token = var.dev_v2_fastapi_alb_enabled ? data.aws_ssm_parameter.dev_fastapi_webhook_token[0].value : null
}

# Runware webhook token (FastAPI WEBHOOK_TOKEN). Used as the ALB query string condition.
data "aws_ssm_parameter" "dev_fastapi_webhook_token" {
  count = var.dev_v2_fastapi_alb_enabled ? 1 : 0

  name            = "/lookddak/dev/fastapi/webhook-token"
  with_decryption = true
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

  read_admin_password_from_ssm = var.dev_v2_postgresql_read_admin_password_from_ssm
  admin_password_wo            = var.dev_v2_postgresql_admin_password_wo
}

module "dev_v2_db_access" {
  source = "./dev/v2/db-access"

  vpc_id                       = module.dev_v1_network.vpc_id
  subnet_id                    = module.dev_v2_network.private_app_subnet_ids[0]
  mysql_security_group_id      = module.dev_v2_network.security_group_ids["mysql"]
  postgresql_security_group_id = module.dev_v2_network.security_group_ids["postgresql"]
  mysql_endpoint               = module.dev_v2_database.mysql_address
  postgresql_endpoint          = module.dev_v2_database.rds_address
  tunnel_user_name             = module.dev_v2_iam.mq_local_test_user_name
}

# ---------------------------------------------------------------
# V2 dev monitoring server (Grafana, Prometheus, Loki, Alloy)
# - Private App 2a, fixed private IP, Session Manager access only.
# ---------------------------------------------------------------
module "dev_v2_monitoring" {
  source = "./dev/v2/observability"

  vpc_id            = module.dev_v1_network.vpc_id
  subnet_id         = module.dev_v2_network.private_app_subnet_ids[0]
  lambda_subnet_ids = module.dev_v2_network.private_app_subnet_ids
  ecs_cluster_arn   = module.dev_v2_ecs_cluster.cluster_arn
}

module "dev_v2_crawler" {
  source = "./dev/v2/crawler"

  ecs_cluster_arn           = module.dev_v2_ecs_cluster.cluster_arn
  scheduler_role_arn        = module.dev_v2_iam.crawler_scheduler_role_arn
  private_app_subnet_ids    = module.dev_v2_network.private_app_subnet_ids
  crawler_security_group_id = module.dev_v2_network.security_group_ids["crawler"]
}

module "dev_v2_task_definitions" {
  source = "./dev/v2/task-definitions"

  bucket_name             = module.shared_ecs_taskdef_store.bucket_name
  ecr_repository_urls     = module.dev_ecr.repository_urls
  task_role_arns          = module.dev_v2_iam.task_role_arns
  task_execution_role_arn = module.dev_v2_iam.task_execution_role_arn
  queue_urls              = module.dev_v2_sqs.queue_urls
  log_group_names         = module.dev_v2_logging.log_group_names
  images_bucket_name      = module.dev_s3.images_bucket_name

}

module "dev_v2_ecs_services" {
  source = "./dev/v2/ecs-services"

  create_services        = var.dev_v2_create_services
  spring_tasks_enabled   = var.dev_v2_spring_tasks_enabled
  fastapi_tasks_enabled  = var.dev_v2_fastapi_tasks_enabled
  cluster_arn            = module.dev_v2_ecs_cluster.cluster_arn
  cluster_name           = module.dev_v2_ecs_cluster.cluster_name
  private_app_subnet_ids = module.dev_v2_network.private_app_subnet_ids
  security_group_ids     = module.dev_v2_network.security_group_ids
  target_group_arns      = module.dev_v2_alb.target_group_arns
  task_definition_arns   = var.dev_v2_task_definition_arns
}

module "dev_v2_cicd_deploy_policy" {
  source = "./dev/v2/cicd-deploy-policy"

  deploy_role_names       = module.dev_v1_iam.deploy_role_names
  template_bucket_arn     = module.shared_ecs_taskdef_store.bucket_arn
  ecr_repository_arns     = module.dev_ecr.ecr_repository_arns
  cluster_name            = module.dev_v2_ecs_cluster.cluster_name
  service_names           = module.dev_v2_ecs_services.service_names
  task_role_arns          = module.dev_v2_iam.task_role_arns
  task_execution_role_arn = module.dev_v2_iam.task_execution_role_arn
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

variable "dev_v1_alb_health_check_path" {
  description = "HTTPS path on the V1 dev nginx that returns 200 for the V2 ALB health check (/ returns 307 to /onboarding)"
  type        = string
  default     = "/onboarding"
}

variable "dev_v2_create_services" {
  description = "Create the V2 dev ECS services and their Auto Scaling resources"
  type        = bool
  default     = true
}

# 2026-10-19: MySQL 컷오버 완료(쓰기 대상 = V2 Dev MySQL) 후 다시 켰다 (spring:6).
variable "dev_v2_spring_tasks_enabled" {
  description = "Run V2 dev Spring tasks (false clamps the service to 0 through Auto Scaling min/max)"
  type        = bool
  default     = true
}

# 임시: dev.lookddak.com/api/v2/webhooks/runware?token=<webhook-token> -> FastAPI (경로 그대로 전달).
# 닫을 때 false로 바꿔 apply.
variable "dev_v2_fastapi_alb_enabled" {
  description = "Temporarily expose /api/v2/* on the dev ALB to the V2 FastAPI service"
  type        = bool
  default     = true
}

variable "dev_v2_fastapi_tasks_enabled" {
  description = "Run V2 dev FastAPI tasks after the PostgreSQL switchover is complete"
  type        = bool
  default     = true
}

variable "dev_v2_task_definition_arns" {
  description = "Initial registered V2 task definition revision ARNs keyed by nextjs, spring, and fastapi"
  type        = map(string)
  default = {
    nextjs  = "arn:aws:ecs:ap-northeast-2:686496667254:task-definition/lookddak-dev-v2-nextjs:1"
    spring  = "arn:aws:ecs:ap-northeast-2:686496667254:task-definition/lookddak-dev-v2-spring:1"
    fastapi = "arn:aws:ecs:ap-northeast-2:686496667254:task-definition/lookddak-dev-v2-fastapi:1"
  }
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

output "dev_v2_mq_local_test_user_arn" {
  description = "IAM User ARN for BE and AI developers to test the V2 dev SQS flow locally"
  value       = module.dev_v2_iam.mq_local_test_user_arn
}

output "dev_v2_db_access_instance_id" {
  description = "Private EC2 instance used only for Dev RDS SSM port forwarding"
  value       = module.dev_v2_db_access.instance_id
}

output "dev_v2_db_access_private_ip" {
  description = "Private IP of the Dev RDS SSM port-forwarding instance"
  value       = module.dev_v2_db_access.instance_private_ip
}

output "dev_v2_mysql_tunnel_command" {
  description = "SSM command for the shared MQ test user to open the Dev MySQL tunnel"
  value       = module.dev_v2_db_access.mysql_port_forward_command
}

output "dev_v2_postgresql_tunnel_command" {
  description = "SSM command for the shared MQ test user to open the Dev PostgreSQL tunnel"
  value       = module.dev_v2_db_access.postgresql_port_forward_command
}

output "dev_v2_task_definition_template_s3_keys" {
  description = "V2 dev Task Definition template S3 keys read by app CI"
  value       = module.dev_v2_task_definitions.template_s3_keys
}

output "dev_v2_log_group_names" {
  description = "V2 dev ECS application CloudWatch Log Group names"
  value       = module.dev_v2_logging.log_group_names
}

output "dev_v2_test_domain_name" {
  description = "V2 dev test domain routed to the Application Load Balancer"
  value       = module.dev_v2_alb.test_domain_name
}

output "dev_v2_runtime_secure_parameter_arns" {
  description = "V2 PostgreSQL SecureString ARNs managed manually outside Terraform"
  value       = module.dev_v2_database.secure_parameter_arns
}

output "dev_v2_monitoring_instance_id" {
  description = "Dev monitoring server instance ID"
  value       = module.dev_v2_monitoring.instance_id
}

output "dev_v2_monitoring_private_ip" {
  description = "Fixed private IP of the dev monitoring server"
  value       = module.dev_v2_monitoring.private_ip
}

output "dev_v2_monitoring_grafana_tunnel_command" {
  description = "SSM command to open Grafana on localhost:3000"
  value       = "aws ssm start-session --target ${module.dev_v2_monitoring.instance_id} --document-name AWS-StartPortForwardingSession --parameters portNumber=3000,localPortNumber=3000"
}
