data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

data "aws_region" "current" {}

locals {
  crawler_task_definition_family_arn = "arn:${data.aws_partition.current.partition}:ecs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:task-definition/lookddak-dev-v2-crawler"
}

resource "aws_scheduler_schedule_group" "crawler" {
  name = "lookddak-dev-v2"

  tags = {
    Component   = "scheduler"
    Environment = "dev"
    Service     = "crawler"
    Version     = "v2"
  }
}

resource "aws_scheduler_schedule" "crawler" {
  name        = "lookddak-dev-v2-crawler"
  group_name  = aws_scheduler_schedule_group.crawler.name
  description = "Run the LookDDak dev V2 crawler every day at 16:15 Asia/Seoul"
  state       = "ENABLED"

  schedule_expression          = "cron(15 16 * * ? *)"
  schedule_expression_timezone = "Asia/Seoul"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = var.ecs_cluster_arn
    role_arn = var.scheduler_role_arn

    ecs_parameters {
      task_definition_arn = local.crawler_task_definition_family_arn
      launch_type         = "FARGATE"
      platform_version    = "LATEST"
      task_count          = 1

      network_configuration {
        assign_public_ip = false
        subnets          = var.private_app_subnet_ids
        security_groups  = [var.crawler_security_group_id]
      }
    }

    retry_policy {
      maximum_event_age_in_seconds = 3600
      maximum_retry_attempts       = 2
    }
  }
}
