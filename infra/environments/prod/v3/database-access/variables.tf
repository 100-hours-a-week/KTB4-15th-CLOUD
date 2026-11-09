variable "eks_cluster_security_group_id" {
  description = "Prod V3 EKS Cluster Security Group ID"
  type        = string
}

variable "mysql_security_group_id" {
  description = "Existing Prod V2 MySQL Security Group ID"
  type        = string
}

variable "mysql_endpoint" {
  description = "Existing Prod V2 MySQL endpoint"
  type        = string
}

variable "postgresql_security_group_id" {
  description = "Existing Prod V2 PostgreSQL Security Group ID"
  type        = string
}

variable "postgresql_endpoint" {
  description = "Existing Prod V2 PostgreSQL endpoint"
  type        = string
}

variable "postgresql_port" {
  description = "Existing Prod V2 PostgreSQL port"
  type        = number
}

variable "db_access_instance_id" {
  description = "SSM managed instance used to bootstrap the database users"
  type        = string
}

variable "db_access_instance_role_name" {
  description = "IAM role name attached to the database access instance"
  type        = string
}
