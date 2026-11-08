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

variable "route53_zone_id" {
  description = "cert-manager DNS-01 검증 대상 lookddak.com Hosted Zone ID"
  type        = string
}

variable "alert_queue_arn" {
  description = "Argo CD Notifications가 실패 이벤트를 보낼 중앙 Alert Queue ARN"
  type        = string
}
