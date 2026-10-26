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

data "aws_ssm_parameter" "prod_fastapi_webhook_token" {
  name            = "/lookddak/prod/fastapi/webhook-token"
  with_decryption = true
}

module "prod_v2_edge" {
  source = "./prod/v2/edge"

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }

  vpc_id                = module.prod_v1_network.vpc_id
  public_subnet_ids     = module.prod_v2_network.alb_public_subnet_ids
  alb_security_group_id = module.prod_v2_network.security_group_ids["alb"]
  route53_zone_id       = module.shared_core.route53_zone_id
  fastapi_webhook_token = data.aws_ssm_parameter.prod_fastapi_webhook_token.value

  access_logs_bucket = module.prod_v2_monitoring.alb_logs_bucket_name
}

# ---------------------------------------------------------------
# V2 prod monitoring server (Grafana, Prometheus, Loki, Tempo, Alloy) - dev와 같은 모듈
# - Private App 2a, fixed private IP, Session Manager access only.
# - Grafana: grafana.lookddak.com → CloudFront → ALB(원본 검증 헤더) → Monitoring EC2:3000
#   ALB 보안 그룹은 CloudFront 대역만 받으므로 ALB에 직접 붙이지 않는다.
# ---------------------------------------------------------------
module "prod_v2_monitoring" {
  source = "../modules/observability"

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }

  environment = "prod"

  vpc_id            = module.prod_v1_network.vpc_id
  subnet_id         = module.prod_v2_network.private_app_subnet_ids[0]
  lambda_subnet_ids = module.prod_v2_network.private_app_subnet_ids
  ecs_cluster_arn   = module.prod_v2_ecs_cluster.cluster_arn

  grafana_domain_name   = "grafana.lookddak.com"
  route53_zone_id       = module.shared_core.route53_zone_id
  https_listener_arn    = module.prod_v2_edge.https_listener_arn
  alb_security_group_id = module.prod_v2_network.security_group_ids["alb"]
  alb_dns_name          = module.prod_v2_edge.alb_dns_name
  alb_zone_id           = module.prod_v2_edge.alb_zone_id

  # Spring(/api/*, 10)·SSE(6) 규칙은 호스트 조건 없이 원본 검증 헤더만 본다.
  # Grafana도 /api/*를 쓰므로 그보다 먼저 평가되게 둔다 (로그아웃 1 → Grafana 2).
  grafana_logout_listener_rule_priority = 1
  grafana_listener_rule_priority        = 2

  grafana_cloudfront_enabled         = true
  grafana_origin_domain_name         = module.prod_v2_edge.origin_domain_name
  grafana_origin_verify_header_value = module.prod_v2_edge.origin_verify_header_value

  ecs_task_security_group_ids = {
    for service in ["nextjs", "spring", "fastapi"] :
    service => module.prod_v2_network.security_group_ids[service]
  }
  mysql_security_group_id      = module.prod_v2_network.security_group_ids["mysql"]
  postgresql_security_group_id = module.prod_v2_network.security_group_ids["postgresql"]

  taskdef_bucket_name = module.shared_ecs_taskdef_store.bucket_name
  taskdef_bucket_arn  = module.shared_ecs_taskdef_store.bucket_arn
  firelens_task_role_names = {
    for service in ["nextjs", "spring", "fastapi"] :
    service => module.prod_v2_iam.task_role_names[service]
  }
  app_log_group_names = module.prod_v2_logging.log_group_names

  db_query_log_instance_ids        = ["lookddak-prod-v2-mysql", "lookddak-prod-v2-postgresql"]
  extra_subscribed_log_group_names = ["/lookddak/prod/v2/crawler"]
}

module "prod_v2_ecs_cluster" {
  source = "./prod/v2/ecs-cluster"
}

module "prod_v2_logging" {
  source = "./prod/v2/logging"
}

module "prod_v2_sqs" {
  source = "./prod/v2/sqs"
}

module "prod_v2_iam" {
  source = "./prod/v2/iam"

  ecs_cluster_arn     = module.prod_v2_ecs_cluster.cluster_arn
  ecr_repository_arns = values(module.shared_core.ecr_repository_arns)
  log_group_arns      = values(module.prod_v2_logging.log_group_arns)
  sqs_queue_arns      = module.prod_v2_sqs.queue_arns
}

module "prod_v2_database" {
  source = "./prod/v2/database"

  db_subnet_ids                = module.prod_v1_network.db_subnet_ids
  postgresql_security_group_id = module.prod_v2_network.security_group_ids["postgresql"]
  mysql_security_group_id      = module.prod_v2_network.security_group_ids["mysql"]

  read_admin_password_from_ssm = var.prod_v2_postgresql_read_admin_password_from_ssm
  admin_password_wo            = var.prod_v2_postgresql_admin_password_wo
}

module "prod_v2_crawler" {
  source = "./prod/v2/crawler"

  ecs_cluster_arn              = module.prod_v2_ecs_cluster.cluster_arn
  scheduler_role_arn           = module.prod_v2_iam.crawler_scheduler_role_arn
  task_execution_role_arn      = module.prod_v2_iam.task_execution_role_arn
  crawler_task_role_arn        = module.prod_v2_iam.task_role_arns["crawler"]
  private_app_subnet_ids       = module.prod_v2_network.private_app_subnet_ids
  crawler_security_group_id    = module.prod_v2_network.security_group_ids["crawler"]
  database_url_parameter_name  = "/lookddak/prod/v2/postgresql/app/database-url"
  crawler_cloudwatch_log_group = module.prod_v2_logging.log_group_names["crawler"]
}

module "prod_v2_task_definitions" {
  source = "./prod/v2/task-definitions"

  bucket_name             = module.shared_ecs_taskdef_store.bucket_name
  ecr_repository_urls     = module.shared_core.ecr_repository_urls
  task_role_arns          = module.prod_v2_iam.task_role_arns
  task_execution_role_arn = module.prod_v2_iam.task_execution_role_arn
  queue_urls              = module.prod_v2_sqs.queue_urls
  log_group_names         = module.prod_v2_logging.log_group_names
  images_bucket_name      = module.prod_s3.images_bucket_name
  fluent_bit_config_arn   = module.prod_v2_monitoring.fluent_bit_config_arn
  fluent_bit_parsers_arn  = module.prod_v2_monitoring.fluent_bit_parsers_arn
}

module "prod_v2_ecs_services" {
  source = "./prod/v2/ecs-services"

  # The FastAPI target group must be attached to the ALB listener before ECS
  # updates the service load balancer configuration.
  depends_on = [module.prod_v2_edge]

  create_services        = var.prod_v2_create_services
  activate_services      = var.prod_v2_activate_services
  service_capacity       = var.prod_v2_service_capacity
  cluster_arn            = module.prod_v2_ecs_cluster.cluster_arn
  cluster_name           = module.prod_v2_ecs_cluster.cluster_name
  private_app_subnet_ids = module.prod_v2_network.private_app_subnet_ids
  security_group_ids     = module.prod_v2_network.security_group_ids
  target_group_arns      = module.prod_v2_edge.target_group_arns
  task_definition_arns   = var.prod_v2_task_definition_arns
}

module "prod_v2_cicd_deploy_policy" {
  source = "./prod/v2/cicd-deploy-policy"

  deploy_role_names = merge(module.prod_v1_iam.deploy_role_names, {
    crawler = module.prod_v1_iam.crawler_deploy_role_name
  })
  template_bucket_arn     = module.shared_ecs_taskdef_store.bucket_arn
  ecr_repository_arns     = module.shared_core.ecr_repository_arns
  cluster_name            = module.prod_v2_ecs_cluster.cluster_name
  service_names           = module.prod_v2_ecs_services.service_names
  task_role_arns          = module.prod_v2_iam.task_role_arns
  task_execution_role_arn = module.prod_v2_iam.task_execution_role_arn
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

variable "prod_v2_create_services" {
  description = "Create the V2 prod ECS services and their Auto Scaling resources"
  type        = bool
  default     = true
}

# 2026-10-22: 2.0.0 배포(템플릿 revision)와 Spring SSE 연결 후 활성화.
# DNS 전환 전 v2-prod.lookddak.com으로 동작을 확인한다.
variable "prod_v2_activate_services" {
  description = "Run V2 prod tasks after MySQL and the cutover prerequisites are ready"
  type        = bool
  default     = true
}

variable "prod_v2_service_capacity" {
  description = "Desired and Auto Scaling capacities applied when V2 prod services are activated"
  type = map(object({
    desired_count = number
    min_capacity  = number
    max_capacity  = number
  }))
  default = {
    nextjs = {
      desired_count = 2
      min_capacity  = 2
      max_capacity  = 5
    }
    spring = {
      desired_count = 2
      min_capacity  = 2
      max_capacity  = 5
    }
    fastapi = {
      desired_count = 2
      min_capacity  = 2
      max_capacity  = 5
    }
  }
}

variable "prod_v2_task_definition_arns" {
  description = "Initial registered V2 prod task definition revision ARNs keyed by nextjs, spring, and fastapi"
  type        = map(string)
  default = {
    nextjs  = "arn:aws:ecs:ap-northeast-2:686496667254:task-definition/lookddak-prod-v2-nextjs:1"
    spring  = "arn:aws:ecs:ap-northeast-2:686496667254:task-definition/lookddak-prod-v2-spring:1"
    fastapi = "arn:aws:ecs:ap-northeast-2:686496667254:task-definition/lookddak-prod-v2-fastapi:1"
  }
}

output "prod_v2_task_definition_template_s3_keys" {
  description = "V2 prod Task Definition template S3 keys"
  value       = module.prod_v2_task_definitions.template_s3_keys
}

output "prod_v2_postgresql_parameter_paths" {
  description = "Parameter Store paths used by V2 Prod PostgreSQL"
  value       = module.prod_v2_database.parameter_paths
}

output "prod_v2_postgresql_secure_parameter_arns" {
  description = "V2 Prod PostgreSQL SecureString ARNs managed manually outside Terraform"
  value       = module.prod_v2_database.secure_parameter_arns
}

output "prod_v2_monitoring_instance_id" {
  description = "V2 prod monitoring server instance ID (Session Manager)"
  value       = module.prod_v2_monitoring.instance_id
}

output "prod_v2_grafana_url" {
  description = "V2 prod Grafana URL"
  value       = module.prod_v2_monitoring.grafana_url
}

output "prod_v2_ecs_cluster_name" {
  description = "V2 prod ECS cluster name"
  value       = module.prod_v2_ecs_cluster.cluster_name
}

output "prod_v2_service_connect_namespace_arn" {
  description = "V2 prod Service Connect namespace ARN"
  value       = module.prod_v2_ecs_services.service_connect_namespace_arn
}

output "prod_v2_test_domain_name" {
  description = "V2 prod validation hostname routed to CloudFront"
  value       = module.prod_v2_edge.test_domain_name
}

output "prod_v2_origin_domain_name" {
  description = "V2 prod CloudFront origin hostname routed to the ALB"
  value       = module.prod_v2_edge.origin_domain_name
}

output "prod_v2_cloudfront_distribution_id" {
  description = "V2 prod CloudFront distribution ID"
  value       = module.prod_v2_edge.cloudfront_distribution_id
}

output "prod_v2_sqs_queue_urls" {
  description = "V2 prod fitting main queue URLs"
  value       = module.prod_v2_sqs.queue_urls
}

output "prod_v2_sqs_dlq_urls" {
  description = "V2 prod fitting dead-letter queue URLs"
  value       = module.prod_v2_sqs.dlq_urls
}

output "prod_v2_sqs_alarm_names" {
  description = "V2 prod fitting SQS CloudWatch alarm names"
  value       = module.prod_v2_sqs.alarm_names
}

output "prod_v2_log_group_names" {
  description = "V2 prod ECS application CloudWatch Log Group names"
  value       = module.prod_v2_logging.log_group_names
}

output "prod_v2_task_execution_role_arn" {
  description = "V2 prod ECS Task Execution Role ARN"
  value       = module.prod_v2_iam.task_execution_role_arn
}

output "prod_v2_task_role_arns" {
  description = "V2 prod ECS Task Role ARNs keyed by service name"
  value       = module.prod_v2_iam.task_role_arns
}

output "prod_v2_modal_body_image_worker_user_name" {
  description = "IAM User name used by the production Modal body image worker"
  value       = module.prod_v2_iam.modal_body_image_worker_user_name
}

output "prod_v2_modal_body_image_worker_policy_arn" {
  description = "Upload-only IAM Policy ARN for the production Modal body image worker"
  value       = module.prod_v2_iam.modal_body_image_worker_policy_arn
}

output "prod_v2_crawler_schedule_arn" {
  description = "V2 prod crawler schedule ARN"
  value       = module.prod_v2_crawler.schedule_arn
}

# 2026-10-22 V1 -> V2 DNS 전환: lookddak.com A 레코드를 V2 edge 모듈로 옮긴다 (값은 CloudFront alias로 변경).
moved {
  from = module.prod_v1_edge.aws_route53_record.apex
  to   = module.prod_v2_edge.aws_route53_record.production_ipv4
}
