variable "name_prefix" {
  description = "모니터링 버킷과 IAM Role 이름 접두사"
  type        = string
}

variable "oidc_provider_arn" {
  description = "V3 Dev EKS OIDC Provider ARN"
  type        = string
}

variable "oidc_issuer" {
  description = "https://를 제외한 V3 Dev EKS OIDC Issuer"
  type        = string
}

variable "db_log_instance_ids" {
  description = "db-log-tailer가 로그 파일을 읽을 RDS 인스턴스 ID"
  type        = list(string)
}

variable "object_expiration_days" {
  description = "Loki·Tempo 버킷 객체 만료일 (보존 7일보다 길게 둔다)"
  type        = number
  default     = 14

  validation {
    condition     = var.object_expiration_days > 7
    error_message = "Loki·Tempo 보존 기간(7일)보다 길어야 합니다."
  }
}
