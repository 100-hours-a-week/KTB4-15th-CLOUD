variable "create_services" {
  description = "Create V2 prod ECS services and their Auto Scaling resources"
  type        = bool
  default     = false
}

variable "activate_services" {
  description = "Run V2 prod tasks and enforce the configured minimum capacity"
  type        = bool
  default     = false
}

variable "service_capacity" {
  description = "Desired and Auto Scaling capacities used after V2 prod services are activated"
  type = map(object({
    desired_count = number
    min_capacity  = number
    max_capacity  = number
  }))

  validation {
    condition = alltrue([
      for service in ["nextjs", "spring", "fastapi"] :
      contains(keys(var.service_capacity), service)
    ])
    error_message = "service_capacity must include nextjs, spring, and fastapi."
  }

  validation {
    condition = alltrue([
      for capacity in values(var.service_capacity) :
      capacity.desired_count >= capacity.min_capacity &&
      capacity.min_capacity >= 0 &&
      capacity.max_capacity >= capacity.min_capacity
    ])
    error_message = "Each desired count must be at least min_capacity, and max_capacity must be at least min_capacity."
  }
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
