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

variable "ec2_instance_arn" {
  description = "ARN of the V1 application EC2 instance targeted by SSM deployments"
  type        = string
}
