variable "ecr_repository_arns" {
  description = "ARNs of the dev application ECR repositories"
  type = object({
    nextjs  = string
    spring  = string
    fastapi = string
  })
}

variable "log_group_arns" {
  description = "ARNs of the dev log groups the EC2 instance writes to"
  type        = list(string)
}
