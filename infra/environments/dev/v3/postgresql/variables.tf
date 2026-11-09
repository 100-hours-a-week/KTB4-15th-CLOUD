variable "postgresql_endpoint" {
  description = "기존 Dev V2 PostgreSQL RDS Endpoint"
  type        = string
}

variable "postgresql_port" {
  description = "기존 Dev V2 PostgreSQL RDS Port"
  type        = number
  default     = 5432
}

variable "db_access_instance_id" {
  description = "V3 PostgreSQL 초기화 Runbook을 실행할 SSM DB Access Node ID"
  type        = string
}

variable "db_access_instance_role_name" {
  description = "SSM DB Access Node IAM Role 이름"
  type        = string
}
