variable "ecs_cluster_arn" {
  description = "V2 prod ECS Cluster ARN targeted by EventBridge Scheduler"
  type        = string
}

variable "scheduler_role_arn" {
  description = "EventBridge Scheduler execution role ARN"
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
  description = "V2 prod crawler security group ID"
  type        = string
}
