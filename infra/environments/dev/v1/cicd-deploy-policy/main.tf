# ---------------------------------------------------------------
# 앱 레포(FE/BE/AI) dev CD 배포 Role의 정책
# - dev ECR 이미지 조회 + SSM Run Command로 dev EC2에서 deploy.sh 실행
# - 배포 대상은 dev EC2 하나뿐이다 (prod EC2에는 명령을 보낼 수 없다)
# - Run Command 출력은 EC2 인스턴스 Role 권한으로 /lookddak/dev/deploy에 저장되므로
#   이 정책에는 CloudWatch Logs 권한이 필요 없다.
# ---------------------------------------------------------------
data "aws_region" "current" {}

locals {
  # SSM이 제공하는 AWS 관리형 문서라 ARN에 계정 ID가 없다.
  run_shell_script_document_arn = "arn:aws:ssm:${data.aws_region.current.region}::document/AWS-RunShellScript"

  # 서비스 키 => 이미지 저장소 서비스 이름
  deploy_targets = {
    fe = "nextjs"
    be = "spring"
    ai = "fastapi"
  }
}

resource "aws_iam_role_policy" "deploy" {
  for_each = local.deploy_targets

  name = "${each.key}-dev-cd-deploy-rolePolicy"
  role = var.deploy_role_names[each.key]
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action   = "ecr:DescribeImages"
      Effect   = "Allow"
      Resource = var.ecr_repository_arns[each.value]
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
  })
}
