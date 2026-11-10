output "queue_urls" {
  description = "로컬 피팅 테스트 Main Queue URL"
  value       = { for name, queue in aws_sqs_queue.main : name => queue.url }
}

output "queue_arns" {
  description = "로컬 피팅 테스트 Main Queue ARN"
  value       = { for name, queue in aws_sqs_queue.main : name => queue.arn }
}

output "dlq_urls" {
  description = "로컬 피팅 테스트 DLQ URL"
  value       = { for name, queue in aws_sqs_queue.dlq : name => queue.url }
}

output "dlq_arns" {
  description = "로컬 피팅 테스트 DLQ ARN"
  value       = { for name, queue in aws_sqs_queue.dlq : name => queue.arn }
}

output "iam_policy_arn" {
  description = "공유 로컬 테스트 사용자에 연결한 Queue 최소 권한 Policy ARN"
  value       = aws_iam_policy.local_test.arn
}
