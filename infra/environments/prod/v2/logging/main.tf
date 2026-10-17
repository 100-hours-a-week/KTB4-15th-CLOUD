locals {
  log_groups = {
    nextjs  = "/lookddak/prod/v2/nextjs"
    spring  = "/lookddak/prod/v2/spring"
    fastapi = "/lookddak/prod/v2/fastapi"
    crawler = "/lookddak/prod/v2/crawler"
  }
}

resource "aws_cloudwatch_log_group" "this" {
  for_each = local.log_groups

  name              = each.value
  retention_in_days = 30

  tags = {
    Component   = "logs"
    Environment = "prod"
    Service     = each.key
    Version     = "v2"
  }
}
