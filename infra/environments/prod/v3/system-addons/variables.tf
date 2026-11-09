variable "cluster_name" {
  description = "System Add-on을 설치할 EKS 클러스터 이름"
  type        = string
}

variable "coredns_addon_version" {
  description = "EKS Kubernetes 버전과 호환되는 CoreDNS Add-on 버전"
  type        = string
  default     = "v1.14.7-eksbuild.22"
}

variable "ebs_csi_driver_addon_version" {
  description = "EKS Kubernetes 버전과 호환되는 EBS CSI Driver Add-on 버전"
  type        = string
  default     = "v1.67.2-eksbuild.1"
}

variable "ebs_csi_driver_role_arn" {
  description = "EBS CSI Controller ServiceAccount에 붙일 IRSA Role ARN"
  type        = string
}

