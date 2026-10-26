variable "vpc_id" {
  description = "Prod VPC ID"
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
  description = "V2 Prod ALB security group ID"
  type        = string
}

variable "route53_zone_id" {
  description = "lookddak.com Route 53 hosted zone ID"
  type        = string
}

variable "fastapi_webhook_token" {
  description = "Runware webhook token required in the query string (?token=) for the FastAPI route"
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^[A-Za-z0-9_-]+$", var.fastapi_webhook_token))
    error_message = "fastapi_webhook_token must be URL-safe ([A-Za-z0-9_-]); ALB treats * and ? as wildcards."
  }
}

variable "origin_domain_name" {
  description = "Regional ALB origin hostname"
  type        = string
  default     = "origin-v2-prod.lookddak.com"
}

variable "test_domain_name" {
  description = "V2 Prod validation hostname routed to CloudFront"
  type        = string
  default     = "v2-prod.lookddak.com"
}

variable "production_domain_name" {
  description = "Production hostname included in the certificate for the later cutover"
  type        = string
  default     = "lookddak.com"
}

variable "production_www_domain_name" {
  description = "Production www hostname included in the certificate for the later cutover"
  type        = string
  default     = "www.lookddak.com"
}

variable "access_logs_bucket" {
  description = "ALB 액세스 로그 S3 버킷 (null이면 끈다)"
  type        = string
  default     = null
}
