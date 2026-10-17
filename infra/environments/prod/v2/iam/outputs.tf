output "task_execution_role_arn" {
  description = "V2 prod ECS Task Execution Role ARN"
  value       = aws_iam_role.task_execution.arn
}

output "task_execution_role_name" {
  description = "V2 prod ECS Task Execution Role name"
  value       = aws_iam_role.task_execution.name
}

output "task_role_arns" {
  description = "V2 prod service ECS Task Role ARNs"
  value       = { for service, role in aws_iam_role.task : service => role.arn }
}

output "task_role_names" {
  description = "V2 prod service ECS Task Role names"
  value       = { for service, role in aws_iam_role.task : service => role.name }
}

output "crawler_scheduler_role_arn" {
  description = "V2 prod Crawler EventBridge Scheduler Role ARN"
  value       = aws_iam_role.crawler_scheduler.arn
}

output "crawler_scheduler_role_name" {
  description = "V2 prod Crawler EventBridge Scheduler Role name"
  value       = aws_iam_role.crawler_scheduler.name
}
