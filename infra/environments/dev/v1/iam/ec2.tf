# ---------------------------------------------------------------
# V1 dev EC2 인스턴스 Role
# - prod EC2 Role(ec2-ssm)과 같은 권한 구성, 대상은 dev 리소스로만 한정
#   · SSM 접속, ECR pull, Parameter Store 읽기(/lookddak/dev/*), S3 dev 이미지 버킷 읽기·쓰기
# - V1 dev에는 모니터링(로그 그룹·알림)을 두지 않으므로 CloudWatch Logs, EventBridge 권한은 넣지 않는다.
# ---------------------------------------------------------------
resource "aws_iam_role" "ec2" {
  name        = "lookddak-dev-ec2"
  description = "LookDDak dev EC2 instance role"
  assume_role_policy = jsonencode({
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
    Version = "2012-10-17"
  })

  tags = {
    Environment = "dev"
  }
}

resource "aws_iam_instance_profile" "ec2" {
  name = "lookddak-dev-ec2"
  role = aws_iam_role.ec2.name

  tags = {
    Environment = "dev"
  }
}

resource "aws_iam_policy" "ec2_ssm_core" {
  name        = "lookddak-dev-ec2-ssm-core"
  description = "SSM managed-node and Session Manager access without broad Parameter Store reads"
  policy = jsonencode({
    Statement = [{
      Action   = ["ssm:DescribeAssociation", "ssm:GetDeployablePatchSnapshotForInstance", "ssm:GetDocument", "ssm:DescribeDocument", "ssm:GetManifest", "ssm:ListAssociations", "ssm:ListInstanceAssociations", "ssm:PutInventory", "ssm:PutComplianceItems", "ssm:PutConfigurePackageResult", "ssm:UpdateAssociationStatus", "ssm:UpdateInstanceAssociationStatus", "ssm:UpdateInstanceInformation"]
      Effect   = "Allow"
      Resource = "*"
      Sid      = "SystemsManagerManagedNodeCore"
      }, {
      Action   = ["ssmmessages:CreateControlChannel", "ssmmessages:CreateDataChannel", "ssmmessages:OpenControlChannel", "ssmmessages:OpenDataChannel"]
      Effect   = "Allow"
      Resource = "*"
      Sid      = "SessionManagerChannels"
      }, {
      Action   = ["ec2messages:AcknowledgeMessage", "ec2messages:DeleteMessage", "ec2messages:FailMessage", "ec2messages:GetEndpoint", "ec2messages:GetMessages", "ec2messages:SendReply"]
      Effect   = "Allow"
      Resource = "*"
      Sid      = "LegacyEc2MessagesChannels"
    }]
    Version = "2012-10-17"
  })

  tags = {
    Component   = "ec2"
    Environment = "dev"
  }
}

resource "aws_iam_policy" "ec2_ecr_pull" {
  name        = "lookddak-dev-ec2-ecr-pull"
  description = "Pull LookDDak application images from the shared ECR repositories"
  policy = jsonencode({
    Statement = [{
      Action   = "ecr:GetAuthorizationToken"
      Effect   = "Allow"
      Resource = "*"
      Sid      = "AuthenticateToEcr"
      }, {
      Action   = ["ecr:BatchCheckLayerAvailability", "ecr:GetDownloadUrlForLayer", "ecr:BatchGetImage"]
      Effect   = "Allow"
      Resource = [var.ecr_repository_arns.nextjs, var.ecr_repository_arns.spring, var.ecr_repository_arns.fastapi]
      Sid      = "PullLookDDakApplicationImages"
    }]
    Version = "2012-10-17"
  })

  tags = {
    Component   = "ec2"
    Environment = "dev"
  }
}

resource "aws_iam_policy" "ec2_parameters_read" {
  name        = "lookddak-dev-ec2-parameters-read"
  description = "Read only LookDDak dev runtime parameters"
  policy = jsonencode({
    Statement = [{
      Action   = ["ssm:GetParameter", "ssm:GetParameters"]
      Effect   = "Allow"
      Resource = "arn:aws:ssm:${local.region}:${local.account_id}:parameter/lookddak/dev/*"
      Sid      = "SsmGetLookddakDevParameters"
      }, {
      Action = "kms:Decrypt"
      Condition = {
        StringEquals = {
          "kms:ViaService" = "ssm.${local.region}.amazonaws.com"
        }
      }
      Effect   = "Allow"
      Resource = "*"
      Sid      = "KmsDecryptViaSsm"
    }]
    Version = "2012-10-17"
  })

  tags = {
    Component   = "ec2"
    Environment = "dev"
  }
}

resource "aws_iam_policy" "ec2_s3_images_rw" {
  name        = "lookddak-dev-ec2-s3-images-rw"
  description = "Read and write objects in the LookDDak dev image bucket"
  policy = jsonencode({
    Statement = [{
      Action   = ["s3:GetBucketLocation", "s3:ListBucket"]
      Effect   = "Allow"
      Resource = local.image_bucket_arn
      Sid      = "ReadImageBucketMetadata"
      }, {
      Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
      Effect   = "Allow"
      Resource = "${local.image_bucket_arn}/*"
      Sid      = "ReadWriteImageObjects"
    }]
    Version = "2012-10-17"
  })

  tags = {
    Component   = "ec2"
    Environment = "dev"
  }
}

locals {
  ec2_policy_arns = {
    ssm_core        = aws_iam_policy.ec2_ssm_core.arn
    ecr_pull        = aws_iam_policy.ec2_ecr_pull.arn
    parameters_read = aws_iam_policy.ec2_parameters_read.arn
    s3_images_rw    = aws_iam_policy.ec2_s3_images_rw.arn
  }
}

resource "aws_iam_role_policy_attachment" "ec2" {
  for_each = local.ec2_policy_arns

  role       = aws_iam_role.ec2.name
  policy_arn = each.value
}
