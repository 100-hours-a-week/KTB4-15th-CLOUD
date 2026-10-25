# ---------------------------------------------------------------
# Crawler 레포 prod CD용 GitHub Actions OIDC Role
# - build: prod ECR(lookddak-crawler) 이미지 push
# - deploy: Role만 여기서 관리하고, V2 배포 정책은 prod/v2/cicd-deploy-policy에서 관리
# - main merge로만 실행된다 (production Environment, main 브랜치).
# ---------------------------------------------------------------
locals {
  crawler_github_repository = "100-hours-a-week@167328634/KTB4-15th-Crawler@1372591446"

  crawler_cicd_assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRoleWithWebIdentity"
      Effect    = "Allow"
      Principal = { Federated = "arn:aws:iam::${local.account_id}:oidc-provider/token.actions.githubusercontent.com" }
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          "token.actions.githubusercontent.com:sub" = [
            "repo:${local.crawler_github_repository}:environment:production",
            "repo:${local.crawler_github_repository}:ref:refs/heads/main",
          ]
        }
      }
    }]
  })
}

resource "aws_iam_role" "crawler_build" {
  name               = "crawler-cd-build-role"
  description        = "LookDDak prod CD build role for KTB4-15th-Crawler (push images to prod ECR)"
  assume_role_policy = local.crawler_cicd_assume_role_policy

  tags = {
    lookddak = "crawler-cd-build-role"
  }
}

resource "aws_iam_role" "crawler_deploy" {
  name               = "crawler-cd-deploy-role"
  description        = "LookDDak prod CD deploy role for KTB4-15th-Crawler (register V2 task definition revisions)"
  assume_role_policy = local.crawler_cicd_assume_role_policy

  tags = {
    lookddak = "crawler-cd-deploy-role"
  }
}

resource "aws_iam_role_policy" "crawler_build" {
  name = "crawler-cd-build-rolePolicy"
  role = aws_iam_role.crawler_build.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "EcrAuth"
      Effect   = "Allow"
      Action   = "ecr:GetAuthorizationToken"
      Resource = "*"
      }, {
      Sid      = "EcrPush"
      Effect   = "Allow"
      Action   = ["ecr:BatchCheckLayerAvailability", "ecr:InitiateLayerUpload", "ecr:UploadLayerPart", "ecr:CompleteLayerUpload", "ecr:PutImage", "ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer"]
      Resource = var.ecr_repository_arns.crawler
    }]
  })
}
