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

variable "fastapi_enabled" {
  description = "Temporarily route /api/v2/* on the dev domains to the V2 FastAPI service"
  type        = bool
  default     = false
}

variable "fastapi_webhook_token" {
  description = "Runware webhook token required in the query string (?token=) for the FastAPI route"
  type        = string
  default     = null
  sensitive   = true

  validation {
    condition     = var.fastapi_webhook_token == null || can(regex("^[A-Za-z0-9_-]+$", var.fastapi_webhook_token))
    error_message = "fastapi_webhook_token must be URL-safe ([A-Za-z0-9_-]); ALB treats * and ? as wildcards."
  }
}

variable "access_logs_bucket" {
  description = "S3 bucket for ALB access logs (prefix alb/). null disables access logs"
  type        = string
  default     = null
}
