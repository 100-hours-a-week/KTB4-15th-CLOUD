variable "db_subnet_ids" {
  description = "RDS DB Subnet Group에 포함할 private DB subnet ID 목록"
  type        = list(string)
}

variable "db_security_group_id" {
  description = "dev RDS에 연결할 보안 그룹 ID"
  type        = string
}

variable "master_username" {
  description = "마스터 사용자 이름 (prod와 동일하게 사용)"
  type        = string
}
