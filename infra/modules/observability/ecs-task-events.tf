# ---------------------------------------------------------------
# ECS task 중지 이벤트 → CloudWatch Logs
# - task가 왜 멈췄는지(OOM, 헬스체크 실패, 배포 교체 등)는 이 이벤트에만 남는다.
# - 이후 이 로그 그룹을 구독해 Loki로 보낸다.
# ---------------------------------------------------------------
resource "aws_cloudwatch_log_group" "ecs_task_stopped" {
  name              = "/aws/events/lookddak-${var.environment}-v2-ecs-task-stopped"
  retention_in_days = 7

  tags = merge(local.common_tags, {
    Name = "lookddak-${var.environment}-v2-ecs-task-stopped"
  })
}

# EventBridge가 로그 그룹에 쓸 수 있게 허용 (CloudWatch Logs 리소스 정책)
resource "aws_cloudwatch_log_resource_policy" "ecs_task_stopped" {
  policy_name = "lookddak-${var.environment}-v2-ecs-task-stopped-events"

  policy_document = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "EventBridgeWriteEcsTaskStopped"
      Effect = "Allow"
      Principal = {
        Service = ["events.amazonaws.com", "delivery.logs.amazonaws.com"]
      }
      Action = [
        "logs:CreateLogStream",
        "logs:PutLogEvents",
      ]
      Resource = "${aws_cloudwatch_log_group.ecs_task_stopped.arn}:*"
    }]
  })
}

resource "aws_cloudwatch_event_rule" "ecs_task_stopped" {
  name        = "lookddak-${var.environment}-v2-ecs-task-stopped"
  description = "${local.environment_title} V2 ECS task stopped events (stop reason, exit codes)"

  event_pattern = jsonencode({
    source        = ["aws.ecs"]
    "detail-type" = ["ECS Task State Change"]
    detail = {
      clusterArn = [var.ecs_cluster_arn]
      lastStatus = ["STOPPED"]
    }
  })

  tags = local.common_tags
}

resource "aws_cloudwatch_event_target" "ecs_task_stopped" {
  rule      = aws_cloudwatch_event_rule.ecs_task_stopped.name
  target_id = "cloudwatch-logs"
  arn       = aws_cloudwatch_log_group.ecs_task_stopped.arn

  depends_on = [aws_cloudwatch_log_resource_policy.ecs_task_stopped]
}
