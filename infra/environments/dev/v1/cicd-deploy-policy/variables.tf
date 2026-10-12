variable "deploy_role_names" {
  description = "Names of the V1 dev application deployment roles"
  type = object({
    fe = string
    be = string
    ai = string
  })
}

variable "ecr_repository_arns" {
  description = "ARNs of the dev application ECR repositories"
  type = object({
    nextjs  = string
    spring  = string
    fastapi = string
  })
}

variable "ec2_instance_arn" {
  description = "SSM Run Command로 배포할 dev EC2 인스턴스 ARN"
  type        = string
}
