variable "create_services" {
  description = "Create V2 prod ECS services and their Auto Scaling resources"
  type        = bool
  default     = false
}

variable "cluster_arn" {
  description = "V2 prod ECS cluster ARN"
  type        = string
}

variable "cluster_name" {
  description = "V2 prod ECS cluster name"
  type        = string
}

variable "private_app_subnet_ids" {
  description = "Private App subnet IDs for V2 prod Fargate tasks"
  type        = list(string)
}

variable "security_group_ids" {
  description = "V2 prod service security group IDs keyed by service name"
  type        = map(string)
}

variable "target_group_arns" {
  description = "V2 prod ALB target group ARNs keyed by service name"
  type        = map(string)
  default     = {}
}

variable "task_definition_arns" {
  description = "Initial registered V2 prod task definition revision ARNs keyed by service name"
  type        = map(string)
  default     = {}
}
