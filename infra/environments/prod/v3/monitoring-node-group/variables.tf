variable "cluster_name" {
  description = "Monitoring Managed Node Group을 연결할 EKS 클러스터 이름"
  type        = string
}

variable "cluster_version" {
  description = "Monitoring Node가 사용할 Kubernetes 버전"
  type        = string
}

variable "subnet_id" {
  description = "Monitoring Node를 둘 Private Node Subnet ID (한 AZ 고정, EBS PV와 같은 AZ)"
  type        = string
}

variable "instance_types" {
  description = "Monitoring Node 인스턴스 타입 (2 vCPU·4 GiB 기준, CPU 크레딧 부족 시 c7g.large)"
  type        = list(string)
  default     = ["t4g.medium"]
}
