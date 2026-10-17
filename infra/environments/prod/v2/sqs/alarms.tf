# Alarm actions remain empty because the existing account-level EventBridge
# rule forwards every lookddak-* alarm state change to the Discord pipeline.
resource "aws_cloudwatch_metric_alarm" "main_queue_age" {
  for_each = local.main_queues

  alarm_name          = "lookddak-prod-v2-sqs-${each.key}-age"
  alarm_description   = "Oldest message in ${aws_sqs_queue.main[each.key].name} exceeded ${each.value.age_alarm_threshold_seconds} seconds"
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateAgeOfOldestMessage"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  threshold           = each.value.age_alarm_threshold_seconds
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = aws_sqs_queue.main[each.key].name
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "dlq_not_empty" {
  for_each = local.main_queues

  alarm_name          = "lookddak-prod-v2-sqs-${each.key}-dlq-not-empty"
  alarm_description   = "A fitting message failed three processing attempts and moved to ${aws_sqs_queue.dlq[each.key].name}"
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 1
  datapoints_to_alarm = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = aws_sqs_queue.dlq[each.key].name
  }

  tags = local.common_tags
}
