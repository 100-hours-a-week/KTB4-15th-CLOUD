output "alert_queue_arn" {
  description = "중앙 Discord 알림 파이프라인이 소비하는 SQS Queue ARN"
  value       = aws_sqs_queue.alert.arn
}
