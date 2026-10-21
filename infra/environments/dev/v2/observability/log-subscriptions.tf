# ---------------------------------------------------------------
# CloudWatch Logs 구독 → lambda-promtail → Alloy → Loki
# - RDS 로그 그룹은 RDS가 만든다 (Terraform 관리 대상 아님). 이름만 참조한다.
#   MySQL: error, slowquery(long_query_time 2초) / PostgreSQL: postgresql
#   (PostgreSQL upgrade 로그는 엔진 업그레이드 때만 생겨 제외)
# - 로그 그룹당 구독 필터는 최대 2개다.
# - 레이블: Alloy가 로그 그룹 경로로 log_group, source(rds, ecs-event, alb)를 붙인다.
# ---------------------------------------------------------------
locals {
  subscribed_log_groups = toset([
    "/aws/rds/instance/lookddak-dev-v2-mysql/error",
    "/aws/rds/instance/lookddak-dev-v2-mysql/slowquery",
    "/aws/rds/instance/lookddak-dev-postgresql/postgresql",
    aws_cloudwatch_log_group.ecs_task_stopped.name,
    aws_cloudwatch_log_group.alb_access.name,
  ])
}

# CloudWatch Logs가 lambda-promtail을 호출할 권한 (로그 그룹별로 한정)
resource "aws_lambda_permission" "cloudwatch_logs" {
  for_each = local.subscribed_log_groups

  statement_id  = "AllowCloudWatchLogs-${substr(md5(each.value), 0, 12)}"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lambda_promtail.function_name
  principal     = "logs.amazonaws.com"
  source_arn    = "arn:${data.aws_partition.current.partition}:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:log-group:${each.value}:*"
}

resource "aws_cloudwatch_log_subscription_filter" "lambda_promtail" {
  for_each = local.subscribed_log_groups

  name            = "lambda-promtail"
  log_group_name  = each.value
  filter_pattern  = ""
  destination_arn = aws_lambda_function.lambda_promtail.arn

  depends_on = [aws_lambda_permission.cloudwatch_logs]
}
