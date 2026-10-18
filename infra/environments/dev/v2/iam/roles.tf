# ---------------------------------------------------------------
# ECS Task Execution Role
# - ECR image pull and runtime secret injection only.
# - CloudWatch Logs permissions are intentionally excluded.
# ---------------------------------------------------------------
resource "aws_iam_role" "task_execution" {
  name               = "lookddak-dev-v2-task-execution"
  description        = "Execution role for LookDDak dev V2 ECS tasks"
  assume_role_policy = local.ecs_tasks_assume_role_policy

  tags = {
    Component   = "ecs"
    Environment = "dev"
    Version     = "v2"
  }
}

# ---------------------------------------------------------------
# Service Task Roles
# - Next.js and crawler intentionally have no AWS permissions.
# - Spring and FastAPI receive only the shared dev S3 policy.
# ---------------------------------------------------------------
resource "aws_iam_role" "task" {
  for_each = local.task_services

  name               = "lookddak-dev-v2-${each.key}-task"
  description        = "Task role for LookDDak dev V2 ${each.key}"
  assume_role_policy = local.ecs_tasks_assume_role_policy

  tags = {
    Component   = "ecs"
    Environment = "dev"
    Service     = each.key
    Version     = "v2"
  }
}

# ---------------------------------------------------------------
# EventBridge Scheduler Role for crawler RunTask
# ---------------------------------------------------------------
resource "aws_iam_role" "crawler_scheduler" {
  name               = "lookddak-dev-v2-crawler-scheduler"
  description        = "EventBridge Scheduler role for the LookDDak dev V2 crawler"
  assume_role_policy = local.scheduler_assume_role_policy

  tags = {
    Component   = "scheduler"
    Environment = "dev"
    Service     = "crawler"
    Version     = "v2"
  }
}

# ---------------------------------------------------------------
# Shared local MQ test role for BE and AI developers
# ---------------------------------------------------------------
resource "aws_iam_role" "mq_local_test" {
  name                 = "lookddak-dev-v2-mq-local-test"
  description          = "Allow BE and AI developers to test the V2 dev SQS flow locally"
  assume_role_policy   = local.mq_local_test_assume_role_policy
  max_session_duration = 3600

  tags = {
    Component   = "sqs"
    Environment = "dev"
    Purpose     = "local-mq-test"
    Version     = "v2"
  }
}
