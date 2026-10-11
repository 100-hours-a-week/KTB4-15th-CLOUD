variable "vpc_id" {
  description = "기존 dev VPC ID"
  type        = string
}

variable "existing_public_subnet_id" {
  description = "기존 dev Public 2a 서브넷 ID"
  type        = string
}

variable "dev_mysql_security_group_id" {
  description = "Spring의 접근을 허용할 기존 dev RDS MySQL 보안 그룹 ID"
  type        = string
}
