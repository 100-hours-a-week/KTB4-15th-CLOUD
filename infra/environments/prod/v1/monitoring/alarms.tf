# ---------------------------------------------------------------
# 서비스 알람
# 이름이 "lookddak-"로 시작하는 알람은 상태가 바뀌면 EventBridge 규칙
# (lookddak-alarm-state-change)이 잡아서 Discord로 보낸다. 그래서 알람 자체의 Action은 없다.
# ---------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "containers_down" {
  alarm_name          = "lookddak-containers-down"
  namespace           = "lookddak-v1-ec2"
  metric_name         = aws_cloudwatch_log_metric_filter.containers_down.metric_transformation[0].name
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 3
  datapoints_to_alarm = 3
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "breaching"
}

resource "aws_cloudwatch_metric_alarm" "container_mem_high" {
  alarm_name          = "lookddak-container-mem-high"
  namespace           = "lookddak-v1-ec2"
  metric_name         = aws_cloudwatch_log_metric_filter.container_mem_max.metric_transformation[0].name
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 5
  datapoints_to_alarm = 5
  threshold           = 90
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "missing"
}

resource "aws_cloudwatch_metric_alarm" "host_mem_high" {
  alarm_name          = "lookddak-host-mem-high"
  namespace           = "lookddak-v1-ec2"
  metric_name         = aws_cloudwatch_log_metric_filter.host_mem.metric_transformation[0].name
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 5
  datapoints_to_alarm = 3
  threshold           = 85
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "missing"
}

resource "aws_cloudwatch_metric_alarm" "nginx_5xx" {
  alarm_name          = "lookddak-nginx-5xx-count"
  namespace           = "Nginx"
  metric_name         = aws_cloudwatch_log_metric_filter.nginx_5xx.metric_transformation[0].name
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  datapoints_to_alarm = 1
  threshold           = 20
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
}

resource "aws_cloudwatch_metric_alarm" "nginx_requests" {
  alarm_name          = "lookddak-nginx-request-count"
  namespace           = "Nginx"
  metric_name         = aws_cloudwatch_log_metric_filter.nginx_requests.metric_transformation[0].name
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  datapoints_to_alarm = 1
  threshold           = 300
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
}

# ---------------------------------------------------------------
# 알림 파이프라인 자체 감시
# Lambda가 Discord 전송에 실패하면 DLQ에 메시지가 쌓인다.
# 이 경우 Discord로는 알릴 수 없으므로 SNS(이메일)로 알린다.
# ---------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "alert_dlq_not_empty" {
  alarm_name          = "alert-pipeline-dlq-not-empty"
  alarm_description   = "Discord 전송 5회 실패 → DLQ에 메시지 쌓임. Lambda 로그 확인 후 DLQ redrive"
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 1
  datapoints_to_alarm = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = aws_sqs_queue.alert_dlq.name
  }

  alarm_actions = [aws_sns_topic.alert_pipeline.arn]
  ok_actions    = [aws_sns_topic.alert_pipeline.arn]
}
