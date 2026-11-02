variable "chart_version" {
  description = "Cilium Helm 차트 버전 (K8s 1.33~1.36 테스트 범위)"
  type        = string
  default     = "1.20.4"
}

variable "cluster_endpoint" {
  description = "EKS API 엔드포인트 (https:// 포함)"
  type        = string
}

variable "operator_role_arn" {
  description = "cilium-operator IRSA Role ARN"
  type        = string
}
