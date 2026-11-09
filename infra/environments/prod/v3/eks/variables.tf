variable "cluster_name" {
  description = "EKS 클러스터 이름"
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes 버전 (Cilium 1.20 테스트 범위 안에서 고정)"
  type        = string
  default     = "1.36"
}

variable "subnet_ids" {
  description = "Control Plane ENI를 둘 서브넷 (node 서브넷 2a/2c)"
  type        = list(string)
}

variable "api_access_security_group_id" {
  description = "API 엔드포인트(443)에 접근할 Prod Monitoring EC2 보안그룹"
  type        = string
}

variable "service_ipv4_cidr" {
  description = "Kubernetes Service(ClusterIP) 대역. VPC·Pod 대역과 겹치지 않아야 한다"
  type        = string
  default     = "172.21.0.0/16"
}

variable "cluster_log_types" {
  description = "CloudWatch로 보낼 EKS Control Plane 로그"
  type        = list(string)
  default     = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
}

variable "cluster_log_retention_days" {
  description = "EKS Control Plane CloudWatch 로그 보존 기간"
  type        = number
  default     = 30
}

variable "deletion_protection" {
  description = "운영 EKS 클러스터 삭제 방지 활성화 여부"
  type        = bool
  default     = true
}

variable "admin_principal_arns" {
  description = "클러스터 관리자 권한을 줄 IAM 주체 ARN (로컬 kubectl/helm용)"
  type        = list(string)
  default     = []
}
