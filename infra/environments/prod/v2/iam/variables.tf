variable "ecs_cluster_arn" {
  description = "V2 prod ECS Cluster ARN targeted by the crawler scheduler"
  type        = string
}

variable "ecr_repository_arns" {
  description = "Shared production ECR repository ARNs that V2 tasks may pull"
  type        = list(string)
}

variable "log_group_arns" {
  description = "V2 prod ECS application CloudWatch Log Group ARNs"
  type        = list(string)
}

variable "sqs_queue_arns" {
  description = "V2 prod fitting main queue ARNs keyed by logical queue name"
  type = object({
    be-fitting-request  = string
    ai-fitting-response = string
    be-fitting-response = string
  })
}
