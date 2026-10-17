variable "deploy_role_names" {
  description = "dev 앱 배포 Role 이름 (fe, be, ai => Role 이름)"
  type = object({
    fe = string
    be = string
    ai = string
  })
}

variable "template_bucket_arn" {
  description = "ECS Task Definition 템플릿 버킷 ARN"
  type        = string
}

variable "ecr_repository_arns" {
  description = "dev ECR 저장소 ARN (서비스 이름 => ARN)"
  type        = map(string)
}

variable "cluster_name" {
  description = "V2 dev ECS Cluster 이름"
  type        = string
}

variable "service_names" {
  description = "V2 dev ECS Service 이름 (서비스 이름 => ECS Service 이름)"
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
