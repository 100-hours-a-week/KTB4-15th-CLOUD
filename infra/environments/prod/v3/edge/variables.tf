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

variable "additional_domain_names" {
  description = "기존 Prod V3 CloudFront에 추가할 검증 도메인"
  type        = set(string)
  default     = []

  validation {
    condition     = alltrue([for domain in var.additional_domain_names : contains(["lookddak.com", "www.lookddak.com", "v3-prod.lookddak.com", "grafana.v3-prod.lookddak.com"], domain)])
    error_message = "Prod V3 추가 도메인은 운영·www·V3 검증·Grafana 도메인만 허용합니다."
  }
}

variable "prevalidated_domain_names" {
  description = "다른 모듈이 이미 관리하는 ACM DNS 검증 레코드를 재사용할 도메인"
  type        = set(string)
  default     = []

  validation {
    condition     = alltrue([for domain in var.prevalidated_domain_names : contains(var.additional_domain_names, domain)])
    error_message = "사전 검증 도메인은 additional_domain_names에도 포함되어야 합니다."
  }
}

variable "cutover_after_distribution_id" {
  description = "Alias를 먼저 해제해야 하는 기존 CloudFront Distribution ID"
  type        = string
  default     = null
  nullable    = true
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
