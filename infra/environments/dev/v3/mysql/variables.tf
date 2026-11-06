variable "mysql_endpoint" {
  description = "기존 Dev V2 MySQL RDS Endpoint"
  type        = string
}

variable "mysql_security_group_id" {
  description = "기존 Dev V2 MySQL RDS Security Group ID"
  type        = string
}

variable "eks_cluster_security_group_id" {
  description = "V3 EKS Node와 Pod ENI가 사용하는 Cluster Security Group ID"
  type        = string
}

variable "db_access_instance_id" {
  description = "V3 MySQL 초기화 Runbook을 실행할 SSM DB Access Node ID"
  type        = string
}

variable "db_access_instance_role_name" {
  description = "SSM DB Access Node IAM Role 이름"
  type        = string
}
