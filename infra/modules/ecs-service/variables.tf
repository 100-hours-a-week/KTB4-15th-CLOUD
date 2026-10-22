variable "create_service" {
  description = "Create the ECS service and its Application Auto Scaling resources"
  type        = bool
  default     = false
}

variable "service_name" {
  description = "ECS service name"
  type        = string
}

variable "cluster_arn" {
  description = "ECS cluster ARN"
  type        = string
}

variable "cluster_name" {
  description = "ECS cluster name used by Application Auto Scaling"
  type        = string
}

variable "task_definition_arn" {
  description = "Initial registered task definition revision ARN"
  type        = string
  default     = null
  nullable    = true
}

variable "desired_count" {
  description = "Initial desired task count"
  type        = number
  default     = 1
}

variable "enable_execute_command" {
  description = "Enable ECS Exec for tasks started by the service"
  type        = bool
  default     = false
}

variable "subnet_ids" {
  description = "Private subnet IDs for Fargate tasks"
  type        = list(string)
}

variable "security_group_ids" {
  description = "Security group IDs for Fargate tasks"
  type        = list(string)
}

variable "target_group_arn" {
  description = "Optional ALB target group ARN"
  type        = string
  default     = null
  nullable    = true
}

variable "additional_load_balancers" {
  description = "Additional ALB target groups attached to the same ECS service"
  type = list(object({
    target_group_arn = string
    container_name   = string
    container_port   = number
  }))
  default = []
}

variable "container_name" {
  description = "Container name referenced by the ECS service load balancer"
  type        = string
}

variable "container_port" {
  description = "Container port"
  type        = number
}

variable "service_connect_namespace_arn" {
  description = "AWS Cloud Map HTTP namespace ARN for ECS Service Connect"
  type        = string
}

variable "service_connect_mode" {
  description = "Service Connect mode: client or client-server"
  type        = string

  validation {
    condition     = contains(["client", "client-server"], var.service_connect_mode)
    error_message = "service_connect_mode must be client or client-server."
  }
}

variable "service_connect_port_name" {
  description = "Named task definition port exposed through Service Connect"
  type        = string
  default     = null
  nullable    = true
}

variable "service_connect_discovery_name" {
  description = "Service Connect discovery name"
  type        = string
  default     = null
  nullable    = true
}

variable "service_connect_dns_name" {
  description = "Service Connect client alias DNS name"
  type        = string
  default     = null
  nullable    = true
}

variable "additional_service_connect_services" {
  description = "Additional named ports exposed through ECS Service Connect"
  type = list(object({
    port_name                   = string
    discovery_name              = optional(string)
    dns_name                    = optional(string)
    client_alias_port           = optional(number)
    idle_timeout_seconds        = optional(number)
    per_request_timeout_seconds = optional(number)
  }))
  default = []
}

variable "autoscaling_min_capacity" {
  description = "Minimum ECS desired count"
  type        = number
}

variable "autoscaling_max_capacity" {
  description = "Maximum ECS desired count"
  type        = number
}

variable "autoscaling_suspended" {
  description = "Suspend dynamic and scheduled ECS service scaling"
  type        = bool
  default     = false
}

variable "cpu_target_value" {
  description = "Optional CPU target tracking percentage"
  type        = number
  default     = null
  nullable    = true
}

variable "cpu_scale_out_cooldown" {
  description = "CPU target tracking scale-out cooldown in seconds"
  type        = number
  default     = 300
}

variable "cpu_scale_in_cooldown" {
  description = "CPU target tracking scale-in cooldown in seconds"
  type        = number
  default     = 300
}

variable "memory_target_value" {
  description = "Optional memory target tracking percentage"
  type        = number
  default     = null
  nullable    = true
}

variable "memory_scale_out_cooldown" {
  description = "Memory target tracking scale-out cooldown in seconds"
  type        = number
  default     = 300
}

variable "memory_scale_in_cooldown" {
  description = "Memory target tracking scale-in cooldown in seconds"
  type        = number
  default     = 300
}

variable "tags" {
  description = "Tags applied to the ECS service"
  type        = map(string)
  default     = {}
}

variable "health_check_grace_period_seconds" {
  description = "Seconds ECS ignores failing load balancer health checks after a task starts (null: not set)"
  type        = number
  default     = null
}
