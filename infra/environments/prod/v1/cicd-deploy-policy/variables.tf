variable "deploy_role_names" {
  description = "Names of the V1 application deployment roles"
  type = object({
    fe = string
    be = string
    ai = string
  })
}

variable "ecr_repository_arns" {
  description = "ARNs of the shared application ECR repositories"
  type = object({
    nextjs  = string
    spring  = string
    fastapi = string
  })
}

variable "ec2_instance_arns" {
  description = "SSM Run Command로 배포할 prod EC2 인스턴스 ARN 목록"
  type        = list(string)
}
