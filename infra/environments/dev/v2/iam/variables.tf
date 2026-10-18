variable "ecs_cluster_arn" {
  description = "Crawler Scheduler가 Task를 실행할 V2 dev ECS Cluster ARN"
  type        = string
}

variable "log_group_arns" {
  description = "V2 dev ECS application CloudWatch Log Group ARNs"
  type        = list(string)
}

variable "sqs_queue_arns" {
  description = "V2 dev fitting main queue ARNs keyed by logical queue name"
  type = object({
    be-fitting-request  = string
    ai-fitting-response = string
    be-fitting-response = string
  })
}

variable "mq_test_trusted_user_names" {
  description = "IAM users allowed to assume the shared V2 dev MQ local test role"
  type        = set(string)

  validation {
    condition     = length(var.mq_test_trusted_user_names) > 0
    error_message = "mq_test_trusted_user_names must contain at least one IAM user name."
  }
}
