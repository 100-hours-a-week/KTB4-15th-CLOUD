variable "vpc_id" {
  description = "Dev VPC ID"
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnet IDs in at least two Availability Zones for the ALB"
  type        = list(string)

  validation {
    condition     = length(var.public_subnet_ids) >= 2
    error_message = "At least two public subnet IDs are required for the ALB."
  }
}

variable "alb_security_group_id" {
  description = "V2 ALB security group ID"
  type        = string
}

variable "route53_zone_id" {
  description = "lookddak.com Route 53 hosted zone ID"
  type        = string
}

variable "domain_name" {
  description = "V2 dev test domain covered by the ALB certificate and routed to the ALB"
  type        = string
}

variable "subject_alternative_names" {
  description = "Additional domains covered by the ALB certificate for a future cutover"
  type        = list(string)
  default     = []
}

variable "v1_domain_name" {
  description = "V1 dev domain routed to the V1 dev EC2 nginx through the ALB"
  type        = string
}

variable "v1_instance_id" {
  description = "V1 dev EC2 instance ID registered in the V1 target group"
  type        = string
}

variable "v1_health_check_path" {
  description = "HTTPS path on the V1 dev nginx that returns 200 for ALB health checks"
  type        = string
}
