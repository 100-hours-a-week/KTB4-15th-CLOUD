output "queue_urls" {
  description = "V3 Dev 피팅 Main Queue URL"
  value       = { for name, queue in aws_sqs_queue.main : name => queue.url }
}

output "queue_arns" {
  description = "V3 Dev 피팅 Main Queue ARN"
  value       = { for name, queue in aws_sqs_queue.main : name => queue.arn }
}

output "dlq_urls" {
  description = "V3 Dev 피팅 DLQ URL"
  value       = { for name, queue in aws_sqs_queue.dlq : name => queue.url }
}

output "dlq_arns" {
  description = "V3 Dev 피팅 DLQ ARN"
  value       = { for name, queue in aws_sqs_queue.dlq : name => queue.arn }
}
