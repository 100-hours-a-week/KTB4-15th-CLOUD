variable "postgresql_security_group_id" {
  description = "기존 Dev V2 PostgreSQL RDS Security Group ID"
  type        = string
}

variable "eks_cluster_security_group_id" {
  description = "V3 EKS Node와 Pod ENI가 사용하는 Cluster Security Group ID"
  type        = string
}
