# ---------------------------------------------------------------
# 앱 레포(FE/BE/AI) dev CD용 GitHub Actions OIDC Role
# - prod Role(prod/v1/iam/cicd.tf)과 분리: develop 브랜치 코드가 prod 권한을 얻지 않게 한다.
# - 신뢰 조건: 각 앱 레포의 develop·hotfix/* 브랜치 또는 develop Environment에서 실행된 워크플로만 허용
#   · develop: 평소 dev 배포
#   · hotfix/*: main에서 분기한 hotfix를 운영 반영 전에 dev 서버에서 검증
#   · environment:develop: job에 environment: develop을 지정한 경우
#     (environment를 지정하면 sub에 브랜치 대신 environment 이름이 들어간다.
#      이때 브랜치 제한은 GitHub Environment의 Deployment branches 설정으로 한다)
# - build: dev ECR 이미지 push만
# - deploy: Role만 여기서 관리하고, 정책은 dev/v1/cicd-deploy-policy에서 관리
#   (정책에 dev EC2 ARN이 필요한데 dev EC2는 이 모듈의 인스턴스 프로파일이 있어야 만들어져 순환 참조가 생긴다)
# ---------------------------------------------------------------
locals {
  github_oidc_provider_arn = "arn:aws:iam::${local.account_id}:oidc-provider/token.actions.githubusercontent.com"

  # GitHub OIDC 토큰의 sub는 조직·저장소 이름 뒤에 ID가 붙는다 (Immutable subject claims)
  github_org = "100-hours-a-week@167328634"

  # 서비스 키 => 앱 레포, 이미지 저장소 서비스 이름
  cicd_services = {
    fe = { repository = "KTB4-15th-FE@1344806631", ecr_service = "nextjs" }
    be = { repository = "KTB4-15th-BE@1344807089", ecr_service = "spring" }
    ai = { repository = "KTB4-15th-AI@1344805395", ecr_service = "fastapi" }
  }

  cicd_assume_role_policies = {
    for k, s in local.cicd_services : k => jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Action    = "sts:AssumeRoleWithWebIdentity"
        Effect    = "Allow"
        Principal = { Federated = local.github_oidc_provider_arn }
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          # hotfix/* 와일드카드를 쓰기 위해 StringLike로 비교한다.
          StringLike = {
            "token.actions.githubusercontent.com:sub" = [
              "repo:${local.github_org}/${s.repository}:ref:refs/heads/develop",
              "repo:${local.github_org}/${s.repository}:ref:refs/heads/hotfix/*",
              "repo:${local.github_org}/${s.repository}:environment:develop",
            ]
          }
        }
      }]
    })
  }
}

resource "aws_iam_role" "build" {
  for_each = local.cicd_services

  name               = "${each.key}-dev-cd-build-role"
  description        = "LookDDak dev CD build role for ${each.value.repository} (push images to dev ECR)"
  assume_role_policy = local.cicd_assume_role_policies[each.key]

  tags = {
    Component   = "cicd"
    Environment = "dev"
  }
}

resource "aws_iam_role" "deploy" {
  for_each = local.cicd_services

  name               = "${each.key}-dev-cd-deploy-role"
  description        = "LookDDak dev CD deploy role for ${each.value.repository} (run deploy.sh on dev EC2)"
  assume_role_policy = local.cicd_assume_role_policies[each.key]

  tags = {
    Component   = "cicd"
    Environment = "dev"
  }
}

resource "aws_iam_role_policy" "build" {
  for_each = local.cicd_services

  name = "${each.key}-dev-cd-build-rolePolicy"
  role = aws_iam_role.build[each.key].name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action   = "ecr:GetAuthorizationToken"
      Effect   = "Allow"
      Resource = "*"
      Sid      = "EcrAuth"
      }, {
      Action   = ["ecr:BatchCheckLayerAvailability", "ecr:GetDownloadUrlForLayer", "ecr:BatchGetImage", "ecr:PutImage", "ecr:InitiateLayerUpload", "ecr:UploadLayerPart", "ecr:CompleteLayerUpload"]
      Effect   = "Allow"
      Resource = var.ecr_repository_arns[each.value.ecr_service]
      Sid      = "EcrPush"
    }]
  })
}
