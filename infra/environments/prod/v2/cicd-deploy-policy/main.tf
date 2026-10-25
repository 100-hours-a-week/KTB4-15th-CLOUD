# ---------------------------------------------------------------
# 앱 레포(FE/BE/AI) prod CD 배포 Role의 V2(ECS) 정책
# - V1 정책(prod/v1/cicd-deploy-policy)과 같은 Role에 따로 붙인다.
#   V1 정책을 지워도 V2 배포가 동작하도록 필요한 권한을 모두 넣는다.
# - 배포 흐름: 템플릿 읽기 → digest 조회 → revision 등록 → 서비스 갱신 → 안정화 확인
# - 각 Role은 자기 서비스의 템플릿·ECR·ECS Service·Task Role만 다룬다.
# - crawler는 ECS Service가 없다 (Scheduler RunTask). revision 등록까지만 허용한다.
# ---------------------------------------------------------------
data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

locals {
  # 배포 Role 키 => 서비스 이름
  deploy_targets = {
    fe      = "nextjs"
    be      = "spring"
    ai      = "fastapi"
    crawler = "crawler"
  }

  service_arn_prefix = "arn:aws:ecs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:service/${var.cluster_name}"
}

resource "aws_iam_role_policy" "deploy" {
  for_each = local.deploy_targets

  name = "${each.key}-prod-v2-cd-deploy-rolePolicy"
  role = var.deploy_role_names[each.key]
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat([{
      Sid      = "TemplateRead"
      Effect   = "Allow"
      Action   = "s3:GetObject"
      Resource = "${var.template_bucket_arn}/prod/v2/${each.value}.json"
      }, {
      Sid      = "EcrDescribe"
      Effect   = "Allow"
      Action   = "ecr:DescribeImages"
      Resource = var.ecr_repository_arns[each.value]
      }, {
      # RegisterTaskDefinition, DescribeTaskDefinition은 리소스 단위 제한을 지원하지 않는다.
      # 등록할 수 있는 Task의 권한은 아래 PassRole로 제한된다.
      Sid      = "TaskDefinitionRegister"
      Effect   = "Allow"
      Action   = ["ecs:RegisterTaskDefinition", "ecs:DescribeTaskDefinition"]
      Resource = "*"
      }, {
      # 템플릿에 태그가 있어 등록 시 TagResource가 함께 필요하다. 등록할 때만 허용한다.
      Sid      = "TaskDefinitionTagOnRegister"
      Effect   = "Allow"
      Action   = "ecs:TagResource"
      Resource = "*"
      Condition = {
        StringEquals = { "ecs:CreateAction" = "RegisterTaskDefinition" }
      }
      }], [
      # crawler는 ECS Service가 없어 서비스 갱신 권한을 넣지 않는다.
      for statement in [{
        Sid      = "ServiceDeploy"
        Effect   = "Allow"
        Action   = ["ecs:UpdateService", "ecs:DescribeServices"]
        Resource = "${local.service_arn_prefix}/${lookup(var.service_names, each.value, "")}"
      }] : statement if each.value != "crawler"
      ], [{
        Sid      = "PassTaskRoles"
        Effect   = "Allow"
        Action   = "iam:PassRole"
        Resource = [var.task_role_arns[each.value], var.task_execution_role_arn]
        Condition = {
          StringEquals = { "iam:PassedToService" = "ecs-tasks.amazonaws.com" }
        }
    }])
  })
}
