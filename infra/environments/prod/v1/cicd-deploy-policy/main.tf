# V1 deployment policies connecting GitHub Actions roles to ECR and EC2.

data "aws_region" "current" {}

locals {
  # SSM이 제공하는 AWS 관리형 문서라 ARN에 계정 ID가 없다.
  run_shell_script_document_arn = "arn:aws:ssm:${data.aws_region.current.region}::document/AWS-RunShellScript"
}

resource "aws_iam_role_policy" "ai_deploy" {
  name = "ai-cd-deploy-rolePolicy"
  policy = jsonencode({
    Statement = [{
      Action   = "ecr:DescribeImages"
      Effect   = "Allow"
      Resource = var.ecr_repository_arns.fastapi
      Sid      = "EcrDescribe"
      }, {
      Action   = "ssm:SendCommand"
      Effect   = "Allow"
      Resource = [local.run_shell_script_document_arn, var.ec2_instance_arn]
      Sid      = "SsmSend"
      }, {
      Action   = "ssm:GetCommandInvocation"
      Effect   = "Allow"
      Resource = "*"
      Sid      = "SsmGetResult"
    }]
    Version = "2012-10-17"
  })
  role = var.deploy_role_names.ai
}

resource "aws_iam_role_policy" "be_deploy" {
  name = "be-cd-deploy-rolePolicy"
  policy = jsonencode({
    Statement = [{
      Action   = "ecr:DescribeImages"
      Effect   = "Allow"
      Resource = var.ecr_repository_arns.spring
      Sid      = "EcrDescribe"
      }, {
      Action   = "ssm:SendCommand"
      Effect   = "Allow"
      Resource = [local.run_shell_script_document_arn, var.ec2_instance_arn]
      Sid      = "SsmSend"
      }, {
      Action   = "ssm:GetCommandInvocation"
      Effect   = "Allow"
      Resource = "*"
      Sid      = "SsmGetResult"
    }]
    Version = "2012-10-17"
  })
  role = var.deploy_role_names.be
}

resource "aws_iam_role_policy" "fe_deploy" {
  name = "fe-cd-deploy-rolePolicy"
  policy = jsonencode({
    Statement = [{
      Action   = "ecr:DescribeImages"
      Effect   = "Allow"
      Resource = var.ecr_repository_arns.nextjs
      Sid      = "EcrDescribe"
      }, {
      Action   = "ssm:SendCommand"
      Effect   = "Allow"
      Resource = [local.run_shell_script_document_arn, var.ec2_instance_arn]
      Sid      = "SsmSend"
      }, {
      Action   = "ssm:GetCommandInvocation"
      Effect   = "Allow"
      Resource = "*"
      Sid      = "SsmGetResult"
    }]
    Version = "2012-10-17"
  })
  role = var.deploy_role_names.fe
}
