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

variable "public_access_cidrs" {
  description = "퍼블릭 API 엔드포인트 허용 대역 (GitHub Actions 러너 IP가 고정이 아니라 dev는 전체 허용, 인증은 IAM)"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "service_ipv4_cidr" {
  description = "Kubernetes Service(ClusterIP) 대역. VPC·Pod 대역과 겹치지 않아야 한다"
  type        = string
  default     = "172.20.0.0/16"
}

variable "cluster_log_types" {
  description = "Control Plane 로그 (CloudWatch). dev는 비용 때문에 끈다"
  type        = list(string)
  default     = []
}

variable "admin_principal_arns" {
  description = "클러스터 관리자 권한을 줄 IAM 주체 ARN (로컬 kubectl/helm용)"
  type        = list(string)
  default     = []
}
