output "service_arn" {
  description = "ECS service ARN when creation is enabled"
  value       = try(aws_ecs_service.this[0].id, null)
}

output "service_name" {
  description = "Configured ECS service name"
  value       = var.service_name
}
