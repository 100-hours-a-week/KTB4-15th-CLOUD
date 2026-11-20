data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

data "aws_region" "current" {}

data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition
  region     = data.aws_region.current.region
  registry   = "${local.account_id}.dkr.ecr.${local.region}.amazonaws.com"

  # ECR 서비스 이름 => GitHub 레포
  services = {
    nextjs  = "KTB4-15th-FE"
    spring  = "KTB4-15th-BE"
    fastapi = "KTB4-15th-AI"
    crawler = "KTB4-15th-Crawler"
  }

  common_tags = {
    Component   = "single-cd"
    Environment = "dev"
    Purpose     = "app-repo-deploy"
  }
}

# ---------------------------------------------------------------
# 서비스별 배포 SSM Document
# - 배포 Role은 임의 명령이 아니라 이 Document만 실행할 수 있다.
# - image는 자기 ECR 저장소의 digest 형식만 허용해 명령 주입을 막는다.
# ---------------------------------------------------------------
resource "aws_ssm_document" "update_image" {
  for_each = local.services

  name            = "lookddak-dev-single-update-${each.key}"
  document_type   = "Command"
  document_format = "JSON"

  content = jsonencode({
    schemaVersion = "2.2"
    description   = "Replace the ${each.key} image on the LookDDak Single Dev host"
    parameters = {
      image = {
        type           = "String"
        description    = "ECR image reference pinned by digest"
        allowedPattern = "^${replace(local.registry, ".", "\\.")}/lookddak-dev-${each.key}@sha256:[a-f0-9]{64}$"
      }
    }
    mainSteps = [{
      action = "aws:runShellScript"
      name   = "updateImage"
      inputs = {
        timeoutSeconds = "900"
        runCommand     = ["/srv/lookddak/scripts/update-image.sh ${each.key} '{{ image }}'"]
      }
    }]
  })

  tags = merge(local.common_tags, {
    Name    = "lookddak-dev-single-update-${each.key}"
    Service = each.key
  })
}

# ---------------------------------------------------------------
# 레포별 GitHub OIDC 배포 Role
# - develop 브랜치에서 실행된 워크플로만 assume할 수 있다.
# ---------------------------------------------------------------
data "aws_iam_policy_document" "assume" {
  for_each = local.services

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_owner}/${each.value}:ref:refs/heads/develop"]
    }
  }
}

resource "aws_iam_role" "deploy" {
  for_each = local.services

  name                 = "gha-lookddak-dev-${each.key}-deploy-role"
  description          = "GitHub Actions develop CD for ${var.github_owner}/${each.value}"
  assume_role_policy   = data.aws_iam_policy_document.assume[each.key].json
  max_session_duration = 3600

  tags = merge(local.common_tags, {
    Name       = "gha-lookddak-dev-${each.key}-deploy-role"
    Service    = each.key
    Repository = "${var.github_owner}/${each.value}"
  })
}

data "aws_iam_policy_document" "deploy" {
  for_each = local.services

  statement {
    sid       = "GetEcrAuthorizationToken"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid = "PushServiceImage"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeImages",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
    ]
    resources = ["arn:${local.partition}:ecr:${local.region}:${local.account_id}:repository/lookddak-dev-${each.key}"]
  }

  statement {
    sid       = "RunServiceUpdateDocument"
    actions   = ["ssm:SendCommand"]
    resources = [aws_ssm_document.update_image[each.key].arn]
  }

  statement {
    sid       = "TargetSingleDevInstance"
    actions   = ["ssm:SendCommand"]
    resources = ["arn:${local.partition}:ec2:${local.region}:${local.account_id}:instance/${var.instance_id}"]
  }

  statement {
    sid = "ReadCommandResult"
    actions = [
      "ssm:GetCommandInvocation",
      "ssm:ListCommandInvocations",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "deploy" {
  for_each = local.services

  name   = "lookddak-dev-${each.key}-deploy"
  role   = aws_iam_role.deploy[each.key].id
  policy = data.aws_iam_policy_document.deploy[each.key].json
}
