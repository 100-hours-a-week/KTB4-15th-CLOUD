output "schedule_group_name" {
  description = "Prod crawler EventBridge Scheduler group name"
  value       = aws_scheduler_schedule_group.crawler.name
}

output "schedule_arn" {
  description = "Prod crawler EventBridge Schedule ARN"
  value       = aws_scheduler_schedule.crawler.arn
}

output "task_definition_family_arn" {
  description = "Prod crawler Task Definition family ARN used by the schedule"
  value       = local.crawler_task_definition_family_arn
}
