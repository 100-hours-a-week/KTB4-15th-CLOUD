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
