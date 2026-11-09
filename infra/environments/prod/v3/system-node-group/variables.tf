variable "cluster_name" {
  description = "System Managed Node Group을 연결할 EKS 클러스터 이름"
  type        = string
}

variable "cluster_version" {
  description = "System Node가 사용할 Kubernetes 버전"
  type        = string
}

variable "subnet_ids" {
  description = "System Node를 배치할 Private Node Subnet ID 목록"
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "System Managed Node Group은 두 개 이상의 AZ에 있는 Node Subnet이 필요합니다."
  }
}
