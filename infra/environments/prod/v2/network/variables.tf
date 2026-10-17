variable "vpc_id" {
  description = "기존 prod VPC ID"
  type        = string
}

variable "existing_public_subnet_id" {
  description = "기존 prod Public 2a 서브넷 ID"
  type        = string
}

variable "prod_app_security_group_id" {
  description = "V2 PostgreSQL 접근과 논리 복제 통신을 허용할 V1 prod EC2 보안 그룹 ID"
  type        = string
}
