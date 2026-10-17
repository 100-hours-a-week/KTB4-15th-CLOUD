# ---------------------------------------------------------------
# V2 dev ECS application logs
# - ECS/Fargate writes container stdout/stderr through awslogs.
# - Log groups are created ahead of task startup and retained for 14 days.
# ---------------------------------------------------------------
locals {
  log_groups = {
    nextjs  = "/lookddak/dev/v2/nextjs"
    spring  = "/lookddak/dev/v2/spring"
    fastapi = "/lookddak/dev/v2/fastapi"
    crawler = "/lookddak/dev/v2/crawler"
  }
}

resource "aws_cloudwatch_log_group" "this" {
  for_each = local.log_groups

  name              = each.value
  retention_in_days = 14

  tags = {
    Component   = "logs"
    Environment = "dev"
    Service     = each.key
    Version     = "v2"
  }
}
