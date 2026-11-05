variable "cluster_name" {
  description = "EKS 클러스터 이름 (AWS LB Controller가 NLB에 붙이는 태그로 NLB를 찾는다)"
  type        = string
}

variable "vpc_id" {
  description = "NLB 보안그룹을 만들 VPC"
  type        = string
}

variable "route53_zone_id" {
  description = "lookddak.com Hosted Zone"
  type        = string
}

variable "domain_names" {
  description = "CloudFront로 받을 도메인. Gateway Listener·인증서 SAN에 있는 이름만 넣는다 (dev.lookddak.com은 V2 전환 때, grafana.dev는 V2 Grafana CloudFront 정리 후)"
  type        = list(string)
}

variable "gateway_service" {
  description = "NLB를 만든 Istio Gateway Service (namespace/name)"
  type        = string
  default     = "istio-ingress/lookddak-gateway-istio"
}

variable "origin_read_timeout" {
  description = "CloudFront가 origin 응답 바이트를 기다리는 시간(초). SSE heartbeat는 이보다 짧아야 한다 (60초 초과는 Service Quota 상향 필요)"
  type        = number
  default     = 60
}
