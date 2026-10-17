resource "aws_iam_role" "task_execution" {
  name               = "lookddak-prod-v2-task-execution"
  description        = "Execution role for LookDDak prod V2 ECS tasks"
  assume_role_policy = local.ecs_tasks_assume_role_policy

  tags = {
    Component   = "ecs"
    Environment = "prod"
    Version     = "v2"
  }
}

resource "aws_iam_role" "task" {
  for_each = local.task_services

  name               = "lookddak-prod-v2-${each.key}-task"
  description        = "Task role for LookDDak prod V2 ${each.key}"
  assume_role_policy = local.ecs_tasks_assume_role_policy

  tags = {
    Component   = "ecs"
    Environment = "prod"
    Service     = each.key
    Version     = "v2"
  }
}

resource "aws_iam_role" "crawler_scheduler" {
  name               = "lookddak-prod-v2-crawler-scheduler"
  description        = "EventBridge Scheduler role for the LookDDak prod V2 crawler"
  assume_role_policy = local.scheduler_assume_role_policy

  tags = {
    Component   = "scheduler"
    Environment = "prod"
    Service     = "crawler"
    Version     = "v2"
  }
}
