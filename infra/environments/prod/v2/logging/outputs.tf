output "log_group_arns" {
  description = "V2 prod ECS application log group ARNs keyed by service name"
  value       = { for service, group in aws_cloudwatch_log_group.this : service => group.arn }
}

output "log_group_names" {
  description = "V2 prod ECS application log group names keyed by service name"
  value       = { for service, group in aws_cloudwatch_log_group.this : service => group.name }
}
