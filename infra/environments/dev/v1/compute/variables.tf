variable "subnet_id" {
  description = "dev EC2를 배치할 public 서브넷 ID"
  type        = string
}

variable "security_group_id" {
  description = "dev EC2에 연결할 애플리케이션 보안 그룹 ID"
  type        = string
}

variable "iam_instance_profile_name" {
  description = "dev EC2에 연결할 IAM 인스턴스 프로파일 이름"
  type        = string
}
