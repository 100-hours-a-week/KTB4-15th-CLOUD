# ---------------------------------------------------------------
# 앱 레포(FE/BE/AI) GitHub Actions 배포 Role의 정책
# - ECR 이미지 조회 + SSM Run Command로 EC2에서 deploy.sh 실행
# - 배포 대상 EC2는 ec2_instance_arns 목록으로 받는다 (prod만, dev는 dev/v1/cicd-deploy-policy)
# ---------------------------------------------------------------
data "aws_region" "current" {}

locals {
  # SSM이 제공하는 AWS 관리형 문서라 ARN에 계정 ID가 없다.
  run_shell_script_document_arn = "arn:aws:ssm:${data.aws_region.current.region}::document/AWS-RunShellScript"

  # 서비스 키 => 배포 Role 이름, 이미지 저장소
  deploy_targets = {
    fe = { role = var.deploy_role_names.fe, ecr_repository_arn = var.ecr_repository_arns.nextjs }
    be = { role = var.deploy_role_names.be, ecr_repository_arn = var.ecr_repository_arns.spring }
    ai = { role = var.deploy_role_names.ai, ecr_repository_arn = var.ecr_repository_arns.fastapi }
  }
}

resource "aws_iam_role_policy" "deploy" {
  for_each = local.deploy_targets

  name = "${each.key}-cd-deploy-rolePolicy"
  role = each.value.role
  policy = jsonencode({
    Statement = [{
      Action   = "ecr:DescribeImages"
      Effect   = "Allow"
      Resource = each.value.ecr_repository_arn
      Sid      = "EcrDescribe"
      }, {
      Action   = "ssm:SendCommand"
      Effect   = "Allow"
      Resource = concat([local.run_shell_script_document_arn], var.ec2_instance_arns)
      Sid      = "SsmSend"
      }, {
      Action   = "ssm:GetCommandInvocation"
      Effect   = "Allow"
      Resource = "*"
      Sid      = "SsmGetResult"
    }]
    Version = "2012-10-17"
  })
}
