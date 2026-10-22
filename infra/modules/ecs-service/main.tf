locals {
  autoscaling_policies = merge(
    var.cpu_target_value == null ? {} : {
      cpu = {
        metric_type        = "ECSServiceAverageCPUUtilization"
        target_value       = var.cpu_target_value
        scale_out_cooldown = var.cpu_scale_out_cooldown
        scale_in_cooldown  = var.cpu_scale_in_cooldown
      }
    },
    var.memory_target_value == null ? {} : {
      memory = {
        metric_type        = "ECSServiceAverageMemoryUtilization"
        target_value       = var.memory_target_value
        scale_out_cooldown = var.memory_scale_out_cooldown
        scale_in_cooldown  = var.memory_scale_in_cooldown
      }
    },
  )
}

resource "aws_ecs_service" "this" {
  count = var.create_service ? 1 : 0

  name                = var.service_name
  cluster             = var.cluster_arn
  task_definition     = var.task_definition_arn
  desired_count       = var.desired_count
  launch_type         = "FARGATE"
  platform_version    = "LATEST"
  scheduling_strategy = "REPLICA"

  enable_ecs_managed_tags = true

  # Only meaningful with a load balancer. Slow-starting tasks (model loading) need time
  # before ALB health checks count, or ECS replaces them in a loop.
  health_check_grace_period_seconds = var.target_group_arn == null && length(var.additional_load_balancers) == 0 ? null : var.health_check_grace_period_seconds
  enable_execute_command            = var.enable_execute_command

  # Rolling update: start new tasks first, stop old tasks only after the new
  # ones are healthy (no capacity drop during deployment).
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  # Stop a failing deployment and roll back to the last completed revision.
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = var.security_group_ids
    assign_public_ip = false
  }

  dynamic "load_balancer" {
    for_each = var.target_group_arn == null ? [] : [var.target_group_arn]

    content {
      target_group_arn = load_balancer.value
      container_name   = var.container_name
      container_port   = var.container_port
    }
  }

  dynamic "load_balancer" {
    for_each = var.additional_load_balancers

    content {
      target_group_arn = load_balancer.value.target_group_arn
      container_name   = load_balancer.value.container_name
      container_port   = load_balancer.value.container_port
    }
  }

  service_connect_configuration {
    enabled   = true
    namespace = var.service_connect_namespace_arn

    dynamic "service" {
      for_each = var.service_connect_mode == "client-server" ? [1] : []

      content {
        port_name      = var.service_connect_port_name
        discovery_name = var.service_connect_discovery_name

        client_alias {
          dns_name = var.service_connect_dns_name
          port     = var.container_port
        }

        dynamic "timeout" {
          for_each = var.service_connect_idle_timeout_seconds == null && var.service_connect_per_request_timeout_seconds == null ? [] : [1]

          content {
            idle_timeout_seconds        = var.service_connect_idle_timeout_seconds
            per_request_timeout_seconds = var.service_connect_per_request_timeout_seconds
          }
        }
      }
    }

    dynamic "service" {
      for_each = var.additional_service_connect_services

      content {
        port_name      = service.value.port_name
        discovery_name = service.value.discovery_name

        dynamic "client_alias" {
          for_each = service.value.dns_name == null || service.value.client_alias_port == null ? [] : [1]

          content {
            dns_name = service.value.dns_name
            port     = service.value.client_alias_port
          }
        }

        dynamic "timeout" {
          for_each = service.value.idle_timeout_seconds == null && service.value.per_request_timeout_seconds == null ? [] : [1]

          content {
            idle_timeout_seconds        = service.value.idle_timeout_seconds
            per_request_timeout_seconds = service.value.per_request_timeout_seconds
          }
        }
      }
    }
  }

  lifecycle {
    ignore_changes = [
      task_definition,
      desired_count,
    ]

    precondition {
      condition     = var.task_definition_arn != null
      error_message = "task_definition_arn must be set before create_service is enabled."
    }

    precondition {
      condition = var.service_connect_mode == "client" || alltrue([
        var.service_connect_port_name != null,
        var.service_connect_discovery_name != null,
        var.service_connect_dns_name != null,
      ])
      error_message = "Client-server Service Connect mode requires port, discovery, and DNS names."
    }
  }

  tags = merge(var.tags, {
    Name = var.service_name
  })
}

resource "aws_appautoscaling_target" "this" {
  count = var.create_service ? 1 : 0

  max_capacity       = var.autoscaling_max_capacity
  min_capacity       = var.autoscaling_min_capacity
  resource_id        = "service/${var.cluster_name}/${aws_ecs_service.this[0].name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"

  suspended_state {
    dynamic_scaling_in_suspended  = var.autoscaling_suspended
    dynamic_scaling_out_suspended = var.autoscaling_suspended
    scheduled_scaling_suspended   = var.autoscaling_suspended
  }
}

resource "aws_appautoscaling_policy" "target_tracking" {
  for_each = var.create_service ? local.autoscaling_policies : {}

  name               = "${var.service_name}-${each.key}"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.this[0].resource_id
  scalable_dimension = aws_appautoscaling_target.this[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.this[0].service_namespace

  target_tracking_scaling_policy_configuration {
    target_value       = each.value.target_value
    scale_out_cooldown = each.value.scale_out_cooldown
    scale_in_cooldown  = each.value.scale_in_cooldown

    predefined_metric_specification {
      predefined_metric_type = each.value.metric_type
    }
  }
}
