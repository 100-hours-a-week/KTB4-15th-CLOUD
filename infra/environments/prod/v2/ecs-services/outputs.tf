output "service_connect_namespace_arn" {
  description = "V2 prod Service Connect HTTP namespace ARN"
  value       = aws_service_discovery_http_namespace.service_connect.arn
}

output "service_names" {
  description = "Configured V2 prod ECS service names"
  value = {
    nextjs  = module.nextjs.service_name
    spring  = module.spring.service_name
    fastapi = module.fastapi.service_name
  }
}
