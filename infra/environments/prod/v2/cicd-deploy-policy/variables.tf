variable "deploy_role_names" {
  description = "prod 앱 배포 Role 이름 (fe, be, ai, crawler => Role 이름)"
  type        = map(string)
}

variable "template_bucket_arn" {
  description = "ECS Task Definition 템플릿 버킷 ARN"
  type        = string
}

variable "ecr_repository_arns" {
  description = "ECR 저장소 ARN (서비스 이름 => ARN)"
  type        = map(string)
}

variable "cluster_name" {
  description = "V2 prod ECS Cluster 이름"
  type        = string
}

variable "service_names" {
  description = "V2 prod ECS Service 이름 (서비스 이름 => ECS Service 이름)"
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
