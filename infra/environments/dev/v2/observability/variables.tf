variable "vpc_id" {
  description = "Dev VPC ID"
  type        = string
}

variable "subnet_id" {
  description = "Private App 2a subnet ID for the monitoring server"
  type        = string
}

variable "private_ip_host_number" {
  description = "Host number of the fixed private IP inside the subnet CIDR (e.g. 250 -> 10.30.21.250)"
  type        = number
  default     = 250
}

variable "instance_type" {
  description = "Monitoring server instance type"
  type        = string
  default     = "t4g.medium"
}

variable "root_volume_size" {
  description = "Root volume size in GiB (OS, container images, Prometheus, Loki WAL/cache, Grafana)"
  type        = number
  default     = 30
}

variable "ecs_cluster_arn" {
  description = "Dev V2 ECS cluster ARN for task stopped events"
  type        = string
}

variable "lambda_subnet_ids" {
  description = "Private App subnet IDs (2a, 2c) for lambda-promtail"
  type        = list(string)
}

variable "alb_arn" {
  description = "Dev V2 ALB ARN for access log delivery"
  type        = string
}
