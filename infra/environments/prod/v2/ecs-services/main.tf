resource "aws_service_discovery_http_namespace" "service_connect" {
  name        = "lookddak-prod-v2"
  description = "Service Connect namespace for LookDDak prod V2 services"

  tags = {
    Name        = "lookddak-prod-v2"
    Environment = "prod"
    Version     = "v2"
  }
}

check "service_creation_prerequisites" {
  assert {
    condition = !var.create_services || alltrue([
      contains(keys(var.task_definition_arns), "nextjs"),
      contains(keys(var.task_definition_arns), "spring"),
      contains(keys(var.task_definition_arns), "fastapi"),
      contains(keys(var.target_group_arns), "nextjs"),
      contains(keys(var.target_group_arns), "spring"),
      contains(keys(var.target_group_arns), "fastapi"),
    ])
    error_message = "Task definition ARNs and ALB target group ARNs for nextjs, spring, and fastapi are required before prod services can be enabled."
  }
}

module "nextjs" {
  source = "../../../../modules/ecs-service"

  create_service      = var.create_services
  service_name        = "lookddak-prod-v2-nextjs-service"
  cluster_arn         = var.cluster_arn
  cluster_name        = var.cluster_name
  task_definition_arn = lookup(var.task_definition_arns, "nextjs", null)
  desired_count       = local.effective_service_capacity["nextjs"].desired_count

  subnet_ids         = var.private_app_subnet_ids
  security_group_ids = [var.security_group_ids["nextjs"]]
  target_group_arn   = lookup(var.target_group_arns, "nextjs", null)
  container_name     = "nextjs"
  container_port     = 3000

  service_connect_namespace_arn = aws_service_discovery_http_namespace.service_connect.arn
  service_connect_mode          = "client"

  autoscaling_min_capacity = local.effective_service_capacity["nextjs"].min_capacity
  autoscaling_max_capacity = local.effective_service_capacity["nextjs"].max_capacity
  cpu_target_value         = 60
  cpu_scale_out_cooldown   = 180
  cpu_scale_in_cooldown    = 300

  tags = local.common_tags
}

module "spring" {
  source = "../../../../modules/ecs-service"

  create_service         = var.create_services
  service_name           = "lookddak-prod-v2-spring-service"
  cluster_arn            = var.cluster_arn
  cluster_name           = var.cluster_name
  task_definition_arn    = lookup(var.task_definition_arns, "spring", null)
  desired_count          = local.effective_service_capacity["spring"].desired_count
  enable_execute_command = true

  subnet_ids         = var.private_app_subnet_ids
  security_group_ids = [var.security_group_ids["spring"]]
  target_group_arn   = lookup(var.target_group_arns, "spring", null)
  container_name     = "spring"
  container_port     = 8080
  # SSE 전용 포트(8081). Task Definition에 spring-sse 포트가 있어야 붙일 수 있다 (#304).
  additional_load_balancers = [
    {
      target_group_arn = var.target_group_arns["spring_sse"]
      container_name   = "spring"
      container_port   = 8081
    }
  ]

  service_connect_namespace_arn               = aws_service_discovery_http_namespace.service_connect.arn
  service_connect_mode                        = "client-server"
  service_connect_port_name                   = "spring-http"
  service_connect_discovery_name              = "spring"
  service_connect_dns_name                    = "spring"
  service_connect_per_request_timeout_seconds = 120
  additional_service_connect_services = [
    {
      port_name                   = "spring-sse"
      discovery_name              = "spring-sse"
      dns_name                    = "spring-sse"
      client_alias_port           = 8081
      idle_timeout_seconds        = 60
      per_request_timeout_seconds = 0
    }
  ]

  autoscaling_min_capacity = local.effective_service_capacity["spring"].min_capacity
  autoscaling_max_capacity = local.effective_service_capacity["spring"].max_capacity
  cpu_target_value         = 60
  cpu_scale_out_cooldown   = 120
  cpu_scale_in_cooldown    = 300

  tags = local.common_tags
}

module "fastapi" {
  source = "../../../../modules/ecs-service"

  create_service      = var.create_services
  service_name        = "lookddak-prod-v2-fastapi-service"
  cluster_arn         = var.cluster_arn
  cluster_name        = var.cluster_name
  task_definition_arn = lookup(var.task_definition_arns, "fastapi", null)
  desired_count       = local.effective_service_capacity["fastapi"].desired_count

  subnet_ids         = var.private_app_subnet_ids
  security_group_ids = [var.security_group_ids["fastapi"]]
  container_name     = "fastapi"
  container_port     = 8000

  target_group_arn                  = lookup(var.target_group_arns, "fastapi", null)
  health_check_grace_period_seconds = 240

  service_connect_namespace_arn               = aws_service_discovery_http_namespace.service_connect.arn
  service_connect_mode                        = "client-server"
  service_connect_port_name                   = "fastapi-http"
  service_connect_discovery_name              = "fastapi"
  service_connect_dns_name                    = "fastapi"
  service_connect_per_request_timeout_seconds = 120

  autoscaling_min_capacity  = local.effective_service_capacity["fastapi"].min_capacity
  autoscaling_max_capacity  = local.effective_service_capacity["fastapi"].max_capacity
  cpu_target_value          = 70
  cpu_scale_out_cooldown    = 300
  cpu_scale_in_cooldown     = 300
  memory_target_value       = 70
  memory_scale_out_cooldown = 300
  memory_scale_in_cooldown  = 300

  tags = local.common_tags
}
