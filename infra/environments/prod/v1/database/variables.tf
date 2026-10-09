variable "db_subnet_ids" {
  description = "RDS DB Subnet Group에 포함할 private DB subnet ID 목록"
  type        = list(string)
}

variable "db_security_group_id" {
  description = "MySQL RDS에 연결할 기존 DB security group ID"
  type        = string
}
