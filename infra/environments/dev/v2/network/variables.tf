variable "vpc_id" {
  description = "기존 dev VPC ID"
  type        = string
}

variable "existing_public_subnet_id" {
  description = "기존 dev Public 2a 서브넷 ID"
  type        = string
}

variable "dev_mysql_security_group_id" {
  description = "기존 dev RDS MySQL 보안 그룹 ID (V2 Spring 접근, V2 MySQL과의 복제)"
  type        = string
}

variable "dev_app_security_group_id" {
  description = "V2 PostgreSQL·MySQL 접근을 허용할 V1 dev EC2 보안 그룹 ID"
  type        = string
}
