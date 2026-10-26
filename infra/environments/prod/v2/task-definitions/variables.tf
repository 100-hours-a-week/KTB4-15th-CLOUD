variable "bucket_name" {
  description = "Task Definition 템플릿 버킷 이름"
  type        = string
}

variable "ecr_repository_urls" {
  description = "ECR 저장소 URL (서비스 이름 => URL)"
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
  description = "V2 prod fitting main queue URL (큐 이름 => URL)"
  type        = map(string)
}

variable "log_group_names" {
  description = "V2 prod 서비스별 로그 그룹 이름"
  type        = map(string)
}

variable "images_bucket_name" {
  description = "prod 이미지 버킷 이름"
  type        = string
}

variable "fluent_bit_config_arn" {
  description = "FireLens Loki 출력 설정 파일 S3 객체 ARN (prod 모니터링 모듈 출력)"
  type        = string
}

variable "fluent_bit_parsers_arn" {
  description = "FireLens 여러 줄 합치기 규칙 파일 S3 객체 ARN (prod 모니터링 모듈 출력)"
  type        = string
}

variable "otlp_endpoint" {
  description = "OTLP gRPC 트레이스 수신 주소 (prod 모니터링 서버 Alloy :4317, spring)"
  type        = string
}

variable "otlp_http_endpoint" {
  description = "OTLP HTTP 트레이스 수신 주소 (prod 모니터링 서버 Alloy :4318, nextjs·fastapi)"
  type        = string
}
