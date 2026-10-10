variable "ecr_repository_arns" {
  description = "ARNs of the shared application ECR repositories"
  type = object({
    nextjs  = string
    spring  = string
    fastapi = string
  })
}
