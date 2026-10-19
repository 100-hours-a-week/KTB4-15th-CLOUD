variable "db_subnet_ids" {
  description = "Existing dev Private DB subnet IDs in ap-northeast-2a and 2c"
  type        = list(string)

  validation {
    condition     = length(var.db_subnet_ids) >= 2
    error_message = "At least two private DB subnet IDs are required for Multi-AZ."
  }
}

variable "postgresql_security_group_id" {
  description = "V2 PostgreSQL security group ID"
  type        = string
}

variable "read_admin_password_from_ssm" {
  description = "Read the administrator password from the manually-created SSM SecureString"
  type        = bool
  default     = true
}

variable "admin_password_wo" {
  description = "Plan-only write-only password input when SSM lookup is disabled"
  type        = string
  default     = null
  sensitive   = true
  ephemeral   = true
}

variable "mysql_security_group_id" {
  description = "V2 MySQL security group ID"
  type        = string
}
