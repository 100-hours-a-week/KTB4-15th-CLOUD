variable "vpc_id" {
  description = "기존 dev VPC ID"
  type        = string
}

variable "existing_public_subnet_id" {
  description = "기존 dev Public 2a 서브넷 ID"
  type        = string
}
