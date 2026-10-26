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
