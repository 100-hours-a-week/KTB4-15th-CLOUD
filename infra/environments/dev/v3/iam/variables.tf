variable "cluster_name" {
  description = "EKS 클러스터 이름 (Role 이름 접두사)"
  type        = string
}

variable "oidc_provider_arn" {
  description = "EKS OIDC Provider ARN"
  type        = string
}

variable "oidc_issuer" {
  description = "https:// 를 뺀 OIDC issuer"
  type        = string
}
