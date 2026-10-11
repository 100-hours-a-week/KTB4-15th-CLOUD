# ---------------------------------------------------------------
# 앱 레포(FE/BE/AI) GitHub Actions용 OIDC Role
# - build: ECR 이미지 push (FE는 Sentry auth token 읽기 포함)
# - deploy: Role만 여기서 관리하고, 정책은 prod/v1/cicd-deploy-policy에서 관리
# ---------------------------------------------------------------

resource "aws_iam_role" "ai_build" {
  lifecycle {
    ignore_changes = [tags, tags_all]
  }

  assume_role_policy = jsonencode({
    Statement = [{
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          "token.actions.githubusercontent.com:sub" = ["repo:100-hours-a-week@167328634/KTB4-15th-AI@1344805395:environment:production", "repo:100-hours-a-week@167328634/KTB4-15th-AI@1344805395:ref:refs/heads/feature/cd", "repo:100-hours-a-week@167328634/KTB4-15th-AI@1344805395:ref:refs/heads/main"]
        }
      }
      Effect = "Allow"
      Principal = {
        Federated = "arn:aws:iam::${local.account_id}:oidc-provider/token.actions.githubusercontent.com"
      }
    }]
    Version = "2012-10-17"
  })
  name = "ai-cd-build-role"
  path = "/"
  tags = {
    lookddak = "ai-cd-build-role"
  }
}

resource "aws_iam_role" "ai_deploy" {
  lifecycle {
    ignore_changes = [tags, tags_all]
  }

  assume_role_policy = jsonencode({
    Statement = [{
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          "token.actions.githubusercontent.com:sub" = ["repo:100-hours-a-week@167328634/KTB4-15th-AI@1344805395:environment:production", "repo:100-hours-a-week@167328634/KTB4-15th-AI@1344805395:ref:refs/heads/feature/cd", "repo:100-hours-a-week@167328634/KTB4-15th-AI@1344805395:ref:refs/heads/main"]
        }
      }
      Effect = "Allow"
      Principal = {
        Federated = "arn:aws:iam::${local.account_id}:oidc-provider/token.actions.githubusercontent.com"
      }
    }]
    Version = "2012-10-17"
  })
  name = "ai-cd-deploy-role"
  path = "/"
  tags = {
    lookddak = "ai-cd-deploy-role"
  }
}

resource "aws_iam_role" "be_build" {
  lifecycle {
    ignore_changes = [tags, tags_all]
  }

  assume_role_policy = jsonencode({
    Statement = [{
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        StringLike = {
          "token.actions.githubusercontent.com:sub" = ["repo:100-hours-a-week@167328634/KTB4-15th-BE@1344807089:environment:production", "repo:100-hours-a-week@167328634/KTB4-15th-BE@1344807089:ref:refs/heads/feature/cd", "repo:100-hours-a-week@167328634/KTB4-15th-BE@1344807089:ref:refs/heads/main"]
        }
      }
      Effect = "Allow"
      Principal = {
        Federated = "arn:aws:iam::${local.account_id}:oidc-provider/token.actions.githubusercontent.com"
      }
    }]
    Version = "2012-10-17"
  })
  name = "be-cd-build-role"
  path = "/"
  tags = {
    lookddak = "be-cd-build-role"
  }
}

resource "aws_iam_role" "be_deploy" {
  lifecycle {
    ignore_changes = [tags, tags_all]
  }

  assume_role_policy = jsonencode({
    Statement = [{
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        StringLike = {
          "token.actions.githubusercontent.com:sub" = ["repo:100-hours-a-week@167328634/KTB4-15th-BE@1344807089:environment:production", "repo:100-hours-a-week@167328634/KTB4-15th-BE@1344807089:ref:refs/heads/feature/cd", "repo:100-hours-a-week@167328634/KTB4-15th-BE@1344807089:ref:refs/heads/main"]
        }
      }
      Effect = "Allow"
      Principal = {
        Federated = "arn:aws:iam::${local.account_id}:oidc-provider/token.actions.githubusercontent.com"
      }
    }]
    Version = "2012-10-17"
  })
  name = "be-cd-deploy-role"
  path = "/"
  tags = {}
}

resource "aws_iam_role" "fe_build" {
  lifecycle {
    ignore_changes = [tags, tags_all]
  }

  assume_role_policy = jsonencode({
    Statement = [{
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          "token.actions.githubusercontent.com:sub" = ["repo:100-hours-a-week@167328634/KTB4-15th-FE@1344806631:environment:production", "repo:100-hours-a-week@167328634/KTB4-15th-FE@1344806631:ref:refs/heads/feature/cd", "repo:100-hours-a-week@167328634/KTB4-15th-FE@1344806631:ref:refs/heads/main"]
        }
      }
      Effect = "Allow"
      Principal = {
        Federated = "arn:aws:iam::${local.account_id}:oidc-provider/token.actions.githubusercontent.com"
      }
    }]
    Version = "2012-10-17"
  })
  name = "fe-cd-build-role"
  path = "/"
  tags = {
    lookddak = "fe-cd-build-role"
  }
}

resource "aws_iam_role" "fe_deploy" {
  lifecycle {
    ignore_changes = [tags, tags_all]
  }

  assume_role_policy = jsonencode({
    Statement = [{
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          "token.actions.githubusercontent.com:sub" = ["repo:100-hours-a-week@167328634/KTB4-15th-FE@1344806631:environment:production", "repo:100-hours-a-week@167328634/KTB4-15th-FE@1344806631:ref:refs/heads/feature/cd", "repo:100-hours-a-week@167328634/KTB4-15th-FE@1344806631:ref:refs/heads/main"]
        }
      }
      Effect = "Allow"
      Principal = {
        Federated = "arn:aws:iam::${local.account_id}:oidc-provider/token.actions.githubusercontent.com"
      }
    }]
    Version = "2012-10-17"
  })
  name = "fe-cd-deploy-role"
  path = "/"
  tags = {}
}

resource "aws_iam_role_policy" "ai_build" {
  name = "ai-cd-build-rolePolicy"
  policy = jsonencode({
    Statement = [{
      Action   = "ecr:GetAuthorizationToken"
      Effect   = "Allow"
      Resource = "*"
      Sid      = "EcrAuth"
      }, {
      Action   = ["ecr:BatchCheckLayerAvailability", "ecr:GetDownloadUrlForLayer", "ecr:BatchGetImage", "ecr:PutImage", "ecr:InitiateLayerUpload", "ecr:UploadLayerPart", "ecr:CompleteLayerUpload"]
      Effect   = "Allow"
      Resource = var.ecr_repository_arns.fastapi
      Sid      = "EcrPush"
    }]
    Version = "2012-10-17"
  })
  role = aws_iam_role.ai_build.name
}

resource "aws_iam_role_policy" "be_build" {
  name = "be-cd-build-rolePolicy"
  policy = jsonencode({
    Statement = [{
      Action   = "ecr:GetAuthorizationToken"
      Effect   = "Allow"
      Resource = "*"
      Sid      = "EcrAuth"
      }, {
      Action   = ["ecr:BatchCheckLayerAvailability", "ecr:GetDownloadUrlForLayer", "ecr:BatchGetImage", "ecr:PutImage", "ecr:InitiateLayerUpload", "ecr:UploadLayerPart", "ecr:CompleteLayerUpload"]
      Effect   = "Allow"
      Resource = var.ecr_repository_arns.spring
      Sid      = "EcrPush"
    }]
    Version = "2012-10-17"
  })
  role = aws_iam_role.be_build.name
}

resource "aws_iam_role_policy" "fe_build" {
  name = "fe-cd-build-rolePolicy"
  policy = jsonencode({
    Statement = [{
      Action   = "ecr:GetAuthorizationToken"
      Effect   = "Allow"
      Resource = "*"
      Sid      = "EcrAuth"
      }, {
      Action   = ["ecr:BatchCheckLayerAvailability", "ecr:InitiateLayerUpload", "ecr:UploadLayerPart", "ecr:CompleteLayerUpload", "ecr:PutImage", "ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer"]
      Effect   = "Allow"
      Resource = var.ecr_repository_arns.nextjs
      Sid      = "EcrPush"
      }, {
      Action   = "ssm:GetParameter"
      Effect   = "Allow"
      Resource = "arn:aws:ssm:${local.region}:${local.account_id}:parameter/lookddak/prod/cicd/sentry/auth-token"
      Sid      = "SsmReadSentryAuthToken"
    }]
    Version = "2012-10-17"
  })
  role = aws_iam_role.fe_build.name
}
