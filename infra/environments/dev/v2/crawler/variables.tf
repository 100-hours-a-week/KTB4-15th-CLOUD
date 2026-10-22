variable "ecs_cluster_arn" {
  description = "V2 dev ECS Cluster ARN targeted by EventBridge Scheduler"
  type        = string
}

variable "scheduler_role_arn" {
  description = "Existing EventBridge Scheduler execution role ARN"
  type        = string
}

variable "task_execution_role_arn" {
  description = "ECS task execution role used by the cleanup task"
  type        = string
}

variable "crawler_task_role_arn" {
  description = "Crawler ECS task role ARN"
  type        = string
}

variable "private_app_subnet_ids" {
  description = "Private App subnet IDs used by the crawler Fargate task"
  type        = list(string)

  validation {
    condition     = length(var.private_app_subnet_ids) >= 2
    error_message = "Crawler requires at least two Private App subnets."
  }
}

variable "crawler_security_group_id" {
  description = "Existing V2 crawler security group ID"
  type        = string
}

variable "database_url_parameter_name" {
  description = "SSM SecureString parameter containing the AI PostgreSQL DATABASE_URL"
  type        = string
}

variable "crawler_cloudwatch_log_group" {
  description = "CloudWatch log group shared by crawler batch tasks"
  type        = string
}
