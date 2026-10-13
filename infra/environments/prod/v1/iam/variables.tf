variable "ecr_repository_arns" {
  description = "ARNs of the shared application ECR repositories"
  type = object({
    nextjs  = string
    spring  = string
    fastapi = string
  })
}

variable "postgresql_backup_bucket_arn" {
  description = "운영 PostgreSQL 백업 버킷 ARN"
  type        = string
}

variable "postgresql_backup_kms_key_arn" {
  description = "운영 PostgreSQL 백업 암호화 KMS 키 ARN"
  type        = string
}
