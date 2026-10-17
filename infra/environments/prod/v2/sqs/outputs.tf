output "queue_urls" {
  description = "V2 prod fitting main queue URLs"
  value       = { for name, queue in aws_sqs_queue.main : name => queue.url }
}

output "queue_arns" {
  description = "V2 prod fitting main queue ARNs"
  value       = { for name, queue in aws_sqs_queue.main : name => queue.arn }
}

output "dlq_urls" {
  description = "V2 prod fitting dead-letter queue URLs"
  value       = { for name, queue in aws_sqs_queue.dlq : name => queue.url }
}

output "dlq_arns" {
  description = "V2 prod fitting dead-letter queue ARNs"
  value       = { for name, queue in aws_sqs_queue.dlq : name => queue.arn }
}

output "alarm_names" {
  description = "V2 prod fitting SQS CloudWatch alarm names"
  value = {
    main_queue_age = { for name, alarm in aws_cloudwatch_metric_alarm.main_queue_age : name => alarm.alarm_name }
    dlq_not_empty  = { for name, alarm in aws_cloudwatch_metric_alarm.dlq_not_empty : name => alarm.alarm_name }
  }
}
