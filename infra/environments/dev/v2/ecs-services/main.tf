resource "aws_service_discovery_http_namespace" "service_connect" {
  name        = "lookddak-dev-v2"
  description = "Service Connect namespace for LookDDak dev V2 services"

  tags = {
    Name        = "lookddak-dev-v2"
    Environment = "dev"
    Version     = "v2"
  }
}

module "nextjs" {
  source = "../../../../modules/ecs-service"

  create_service      = var.create_services
  service_name        = "lookddak-dev-v2-nextjs-service"
  cluster_arn         = var.cluster_arn
  cluster_name        = var.cluster_name
  task_definition_arn = lookup(var.task_definition_arns, "nextjs", null)
  desired_count       = 1

  subnet_ids         = var.private_app_subnet_ids
  security_group_ids = [var.security_group_ids["nextjs"]]
  target_group_arn   = var.target_group_arns["nextjs"]
  container_name     = "nextjs"
  container_port     = 3000

  service_connect_namespace_arn = aws_service_discovery_http_namespace.service_connect.arn
  service_connect_mode          = "client"

  autoscaling_min_capacity = 1
  autoscaling_max_capacity = 5
  cpu_target_value         = 60
  cpu_scale_out_cooldown   = 180
  cpu_scale_in_cooldown    = 300

  tags = local.common_tags
}

module "spring" {
  source = "../../../../modules/ecs-service"

  create_service         = var.create_services
  service_name           = "lookddak-dev-v2-spring-service"
  cluster_arn            = var.cluster_arn
  cluster_name           = var.cluster_name
  task_definition_arn    = lookup(var.task_definition_arns, "spring", null)
  desired_count          = 1
  enable_execute_command = true

  subnet_ids         = var.private_app_subnet_ids
  security_group_ids = [var.security_group_ids["spring"]]
  target_group_arn   = var.target_group_arns["spring"]
  container_name     = "spring"
  container_port     = 8080

  service_connect_namespace_arn  = aws_service_discovery_http_namespace.service_connect.arn
  service_connect_mode           = "client-server"
  service_connect_port_name      = "spring-http"
  service_connect_discovery_name = "spring"
  service_connect_dns_name       = "spring"

  autoscaling_min_capacity = 1
  autoscaling_max_capacity = 5
  cpu_target_value         = 60
  cpu_scale_out_cooldown   = 120
  cpu_scale_in_cooldown    = 300

  tags = local.common_tags
}

module "fastapi" {
  source = "../../../../modules/ecs-service"

  create_service      = var.create_services
  service_name        = "lookddak-dev-v2-fastapi-service"
  cluster_arn         = var.cluster_arn
  cluster_name        = var.cluster_name
  task_definition_arn = lookup(var.task_definition_arns, "fastapi", null)
  desired_count       = 1

  subnet_ids         = var.private_app_subnet_ids
  security_group_ids = [var.security_group_ids["fastapi"]]
  container_name     = "fastapi"
  container_port     = 8000

  service_connect_namespace_arn  = aws_service_discovery_http_namespace.service_connect.arn
  service_connect_mode           = "client-server"
  service_connect_port_name      = "fastapi-http"
  service_connect_discovery_name = "fastapi"
  service_connect_dns_name       = "fastapi"

  autoscaling_min_capacity  = 1
  autoscaling_max_capacity  = 5
  cpu_target_value          = 70
  cpu_scale_out_cooldown    = 300
  cpu_scale_in_cooldown     = 300
  memory_target_value       = 70
  memory_scale_out_cooldown = 300
  memory_scale_in_cooldown  = 300

  tags = local.common_tags
}
