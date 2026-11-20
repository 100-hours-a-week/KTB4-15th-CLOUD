variable "instance_id" {
  description = "Single Dev EC2 instance ID targeted by app deployments"
  type        = string
}

variable "github_owner" {
  description = "GitHub organization that owns the app repositories"
  type        = string
  default     = "100-hours-a-week"
}
