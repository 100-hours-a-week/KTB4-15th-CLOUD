data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

data "aws_region" "current" {}

locals {
  crawler_task_definition_family_arn = "arn:${data.aws_partition.current.partition}:ecs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:task-definition/lookddak-prod-v2-crawler"

  cleanup_script = <<-SCRIPT
    set -eu
    iteration=1
    while [ "$iteration" -le 10 ]; do
      deleted_count="$(psql "$DATABASE_URL" -X -v ON_ERROR_STOP=1 -At <<'SQL'
    WITH expired AS (
        SELECT id
        FROM public.price_change_outbox
        WHERE status = 'DONE'
          AND completed_at < CURRENT_TIMESTAMP - INTERVAL '5 days'
        ORDER BY completed_at, id
        LIMIT 1000
    ), deleted AS (
        DELETE FROM public.price_change_outbox AS item
        USING expired
        WHERE item.id = expired.id
          AND item.status = 'DONE'
          AND item.completed_at < CURRENT_TIMESTAMP - INTERVAL '5 days'
        RETURNING item.id
    )
    SELECT count(*) FROM deleted;
    SQL
    )"
      echo "cleanup_iteration=$iteration deleted_count=$deleted_count"
      [ "$deleted_count" -lt 1000 ] && exit 0
      iteration=$((iteration + 1))
    done
    echo "cleanup_iteration_limit_reached=true"
  SCRIPT
}

resource "aws_scheduler_schedule_group" "crawler" {
  name = "lookddak-prod-v2"

  tags = {
    Component   = "scheduler"
    Environment = "prod"
    Service     = "crawler"
    Version     = "v2"
  }
}

resource "aws_scheduler_schedule" "crawler" {
  name        = "lookddak-prod-v2-crawler"
  group_name  = aws_scheduler_schedule_group.crawler.name
  description = "Collect prices and create outbox rows every day at 11:00 Asia/Seoul"
  state       = "ENABLED"

  schedule_expression          = "cron(0 11 * * ? *)"
  schedule_expression_timezone = "Asia/Seoul"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = var.ecs_cluster_arn
    role_arn = var.scheduler_role_arn
    input = jsonencode({
      containerOverrides = [{
        name    = "crawler"
        command = ["--apply"]
      }]
    })

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

resource "aws_scheduler_schedule" "delivery" {
  name        = "lookddak-prod-v2-crawler-delivery"
  group_name  = aws_scheduler_schedule_group.crawler.name
  description = "Deliver due crawler outbox rows to the Backend at 11:40 and 13:40 Asia/Seoul"
  state       = "ENABLED"

  # 수집(11:00, 약 15~20분) 뒤 1회 + 실패분 당일 재시도 1회.
  # 1회 실행 상한: 요청 10회 x 100건 = 1,000건. 남은 건은 다음 실행으로 넘어간다.
  schedule_expression          = "cron(40 11,13 * * ? *)"
  schedule_expression_timezone = "Asia/Seoul"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = var.ecs_cluster_arn
    role_arn = var.scheduler_role_arn
    input = jsonencode({
      containerOverrides = [{
        name    = "crawler"
        command = ["--deliver"]
      }]
    })

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

resource "aws_ecs_task_definition" "cleanup" {
  family                   = "lookddak-prod-v2-crawler-cleanup"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = var.task_execution_role_arn
  task_role_arn            = var.crawler_task_role_arn

  container_definitions = jsonencode([{
    name       = "crawler-cleanup"
    image      = "public.ecr.aws/docker/library/postgres:16-alpine@sha256:deb28ee471183cb0c303113dac9b2433c51eeeeb678def7af9a9ec5820367815"
    essential  = true
    entryPoint = ["/bin/sh", "-c"]
    command    = [local.cleanup_script]
    secrets = [{
      name      = "DATABASE_URL"
      valueFrom = var.database_url_parameter_name
    }]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = var.crawler_cloudwatch_log_group
        awslogs-region        = data.aws_region.current.region
        awslogs-stream-prefix = "cleanup"
      }
    }
  }])

  runtime_platform {
    cpu_architecture        = "X86_64"
    operating_system_family = "LINUX"
  }

  tags = {
    Component   = "cleanup"
    Environment = "prod"
    Service     = "crawler"
    Version     = "v2"
  }
}

resource "aws_scheduler_schedule" "cleanup" {
  name        = "lookddak-prod-v2-crawler-cleanup"
  group_name  = aws_scheduler_schedule_group.crawler.name
  description = "Delete crawler DONE outbox rows older than five days at 04:00 Asia/Seoul"
  state       = "ENABLED"

  schedule_expression          = "cron(0 4 * * ? *)"
  schedule_expression_timezone = "Asia/Seoul"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = var.ecs_cluster_arn
    role_arn = var.scheduler_role_arn

    ecs_parameters {
      task_definition_arn = aws_ecs_task_definition.cleanup.arn
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
