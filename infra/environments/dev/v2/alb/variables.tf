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
  description = "Domain name covered by the ALB certificate"
  type        = string
}
