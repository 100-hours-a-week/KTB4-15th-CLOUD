variable "vpc_id" {
  description = "기존 dev VPC ID (V1 소유)"
  type        = string
}

variable "cluster_name" {
  description = "dev EKS 클러스터 이름 (서브넷 태그에 사용)"
  type        = string
}

variable "pod_cidr_block" {
  description = "Pod 전용 보조 CIDR"
  type        = string
  default     = "100.65.0.0/16"
}

variable "nat_gateway_id" {
  description = "외부 경로에 쓸 NAT Gateway ID (V2 dev 단일 NAT)"
  type        = string
}
