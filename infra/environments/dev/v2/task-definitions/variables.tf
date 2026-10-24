variable "bucket_name" {
  description = "Task Definition 템플릿 버킷 이름"
  type        = string
}

variable "ecr_repository_urls" {
  description = "dev ECR 저장소 URL (서비스 이름 => URL)"
  type        = map(string)
}

variable "task_role_arns" {
  description = "V2 서비스별 Task Role ARN"
  type        = map(string)
}

variable "task_execution_role_arn" {
  description = "V2 Task Execution Role ARN"
  type        = string
}

variable "queue_urls" {
  description = "V2 dev fitting main queue URL (큐 이름 => URL)"
  type        = map(string)
}

variable "log_group_names" {
  description = "V2 dev 서비스별 로그 그룹 이름"
  type        = map(string)
}

variable "images_bucket_name" {
  description = "dev 이미지 버킷 이름"
  type        = string
}

variable "fluent_bit_config_arn" {
  description = "FireLens(Fluent Bit init) 추가 설정 파일 S3 객체 ARN (Loki 출력)"
  type        = string
}

variable "fluent_bit_parsers_arn" {
  description = "FireLens(Fluent Bit init) 여러 줄 합치기 규칙 파일 S3 객체 ARN"
  type        = string
}

variable "otlp_endpoint" {
  description = "OTel 트레이스 수신 주소 (Monitoring EC2 Alloy OTLP gRPC, 예: http://10.30.21.250:4317). spring(Java 에이전트)"
  type        = string
}

variable "otlp_http_endpoint" {
  description = "OTel 트레이스 수신 주소 (Monitoring EC2 Alloy OTLP HTTP, 예: http://10.30.21.250:4318). nextjs·fastapi(공식 Node·Python 이미지)"
  type        = string
}
