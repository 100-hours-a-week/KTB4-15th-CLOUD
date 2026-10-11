output "task_execution_role_arn" {
  description = "V2 ECS Task Execution Role ARN"
  value       = aws_iam_role.task_execution.arn
}

output "task_execution_role_name" {
  description = "V2 ECS Task Execution Role 이름"
  value       = aws_iam_role.task_execution.name
}

output "task_role_arns" {
  description = "V2 서비스별 ECS Task Role ARN"
  value       = { for service, role in aws_iam_role.task : service => role.arn }
}

output "task_role_names" {
  description = "V2 서비스별 ECS Task Role 이름"
  value       = { for service, role in aws_iam_role.task : service => role.name }
}

output "crawler_scheduler_role_arn" {
  description = "V2 Crawler EventBridge Scheduler Role ARN"
  value       = aws_iam_role.crawler_scheduler.arn
}

output "crawler_scheduler_role_name" {
  description = "V2 Crawler EventBridge Scheduler Role 이름"
  value       = aws_iam_role.crawler_scheduler.name
}
