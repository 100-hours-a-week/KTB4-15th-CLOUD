variable "create_services" {
  description = "Create V2 ECS services and their Auto Scaling resources"
  type        = bool
  default     = false
}

variable "spring_tasks_enabled" {
  description = "Run V2 Spring tasks and allow their Auto Scaling policies to act"
  type        = bool
  default     = true
}

variable "fastapi_tasks_enabled" {
  description = "Run V2 FastAPI tasks and allow their Auto Scaling policies to act"
  type        = bool
  default     = true
}

variable "cluster_arn" {
  description = "V2 ECS cluster ARN"
  type        = string
}

variable "cluster_name" {
  description = "V2 ECS cluster name"
  type        = string
}

variable "private_app_subnet_ids" {
  description = "Private App subnet IDs for V2 Fargate tasks"
  type        = list(string)
}

variable "security_group_ids" {
  description = "V2 service security group IDs keyed by service name"
  type        = map(string)
}

variable "target_group_arns" {
  description = "V2 ALB target group ARNs keyed by service name"
  type        = map(string)
}

variable "task_definition_arns" {
  description = "Initial registered task definition revision ARNs keyed by service name"
  type        = map(string)
  default     = {}
}
