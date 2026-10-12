output "schedule_group_name" {
  description = "Crawler EventBridge Scheduler group name"
  value       = aws_scheduler_schedule_group.crawler.name
}

output "schedule_arn" {
  description = "Crawler EventBridge Schedule ARN"
  value       = aws_scheduler_schedule.crawler.arn
}

output "task_definition_family_arn" {
  description = "Crawler Task Definition family ARN used by the schedule"
  value       = local.crawler_task_definition_family_arn
}
