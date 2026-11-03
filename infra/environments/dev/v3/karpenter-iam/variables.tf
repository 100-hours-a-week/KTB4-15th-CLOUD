variable "cluster_name" {
  description = "Karpenter가 Node를 공급할 EKS 클러스터 이름"
  type        = string
}

variable "oidc_provider_arn" {
  description = "Karpenter Controller IRSA에 사용할 EKS OIDC Provider ARN"
  type        = string
}

variable "oidc_issuer" {
  description = "https:// 를 제외한 EKS OIDC Issuer"
  type        = string
}

variable "controller_namespace" {
  description = "Karpenter Controller가 실행될 Kubernetes Namespace"
  type        = string
  default     = "kube-system"
}

variable "controller_service_account" {
  description = "Karpenter Controller ServiceAccount 이름"
  type        = string
  default     = "karpenter"
}
