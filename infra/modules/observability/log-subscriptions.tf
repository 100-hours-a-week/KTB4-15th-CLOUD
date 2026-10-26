# ---------------------------------------------------------------
# CloudWatch Logs 구독 → lambda-promtail → Alloy → Loki
# - RDS 로그(MySQL 감사·error·slowquery, PostgreSQL)는 CloudWatch로 내보내지 않는다.
#   db-log-tailer가 RDS API로 직접 받아 Alloy로 보낸다 (db-query-log.tf).
# - 로그 그룹당 구독 필터는 최대 2개다.
# - 레이블: Alloy가 로그 그룹 경로로 log_group, source(rds, ecs-event, app)·service를 붙인다.
# ---------------------------------------------------------------
locals {
  # extra_subscribed_log_group_names: 사이드카 없이 awslogs로 남기는 로그 그룹(예: 가격 갱신 배치 crawler)
  subscribed_log_groups = toset(concat(
    [aws_cloudwatch_log_group.ecs_task_stopped.name],
    var.extra_subscribed_log_group_names,
  ))
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
