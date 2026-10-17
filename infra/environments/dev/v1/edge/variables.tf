variable "zone_id" {
  description = "lookddak.com Hosted Zone ID"
  type        = string
}

variable "alb_dns_name" {
  description = "V2 dev ALB DNS name that fronts dev.lookddak.com"
  type        = string
}

variable "alb_zone_id" {
  description = "V2 dev ALB canonical hosted zone ID"
  type        = string
}
