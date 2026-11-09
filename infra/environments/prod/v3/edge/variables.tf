variable "cluster_name" {
  description = "NLB를 만든 Prod EKS 클러스터 이름"
  type        = string
}

variable "route53_zone_id" {
  description = "lookddak.com Public Hosted Zone ID"
  type        = string
}

variable "vpc_id" {
  description = "Prod Gateway NLB가 속한 VPC ID"
  type        = string
}

variable "domain_name" {
  description = "Prod Argo CD 외부 도메인"
  type        = string

  validation {
    condition     = var.domain_name == "argocd.lookddak.com"
    error_message = "Prod Argo CD Edge는 argocd.lookddak.com만 사용할 수 있습니다."
  }
}

variable "gateway_service" {
  description = "NLB를 만든 Istio Gateway Service(namespace/name)"
  type        = string
  default     = "istio-ingress/lookddak-gateway-istio"
}

variable "origin_read_timeout" {
  description = "CloudFront가 Origin 응답 바이트를 기다리는 시간(초)"
  type        = number
  default     = 60

  validation {
    condition     = var.origin_read_timeout >= 1 && var.origin_read_timeout <= 60
    error_message = "CloudFront VPC Origin read timeout은 1~60초여야 합니다."
  }
}
