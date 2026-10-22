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

variable "grafana_domain_name" {
  description = "Public domain for Grafana behind the dev V2 ALB"
  type        = string
}

variable "route53_zone_id" {
  description = "Route53 public hosted zone ID for lookddak.com"
  type        = string
}

variable "https_listener_arn" {
  description = "Dev V2 ALB HTTPS listener ARN"
  type        = string
}

variable "alb_security_group_id" {
  description = "Dev V2 ALB security group ID"
  type        = string
}

variable "alb_dns_name" {
  description = "Dev V2 ALB DNS name"
  type        = string
}

variable "alb_zone_id" {
  description = "Dev V2 ALB canonical hosted zone ID"
  type        = string
}

variable "ecs_task_security_group_ids" {
  description = "ECS task security group IDs that run the ecs_exporter sidecar (service => SG ID)"
  type        = map(string)
}
