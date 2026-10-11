# ---------------------------------------------------------------
# V1 EC2 인스턴스 Role (ec2-ssm)
# - SSM 접속, ECR pull, CloudWatch Logs 쓰기, Parameter Store 읽기, S3 이미지 읽기·쓰기
# ---------------------------------------------------------------

resource "aws_iam_role" "ec2" {
  lifecycle {
    ignore_changes = [tags, tags_all]
  }

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
  description = "Allows EC2 instances to call AWS services on your behalf."
  name        = "ec2-ssm"
  path        = "/"
  tags        = {}
}

resource "aws_iam_instance_profile" "ec2" {
  lifecycle {
    ignore_changes = [tags, tags_all]
  }

  name = "ec2-ssm"
  path = "/"
  role = aws_iam_role.ec2.name
  tags = {}
}

resource "aws_iam_policy" "ec2_cloudwatch_logs_write" {
  lifecycle {
    ignore_changes = [tags, tags_all]
  }

  description = "Allow LookDDak EC2 Docker containers to write to production CloudWatch Logs groups"
  name        = "lookddak-prod-ec2-cloudwatch-logs-write"
  path        = "/"
  policy = jsonencode({
    Statement = [{
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Effect   = "Allow"
      Resource = ["arn:aws:logs:${local.region}:${local.account_id}:log-group:/lookddak/prod/nginx:log-stream:*", "arn:aws:logs:${local.region}:${local.account_id}:log-group:/lookddak/prod/nextjs:log-stream:*", "arn:aws:logs:${local.region}:${local.account_id}:log-group:/lookddak/prod/spring:log-stream:*", "arn:aws:logs:${local.region}:${local.account_id}:log-group:/lookddak/prod/fastapi:log-stream:*", "arn:aws:logs:${local.region}:${local.account_id}:log-group:/lookddak/prod/postgresql:log-stream:*"]
      Sid      = "WriteLookDDakContainerLogs"
    }]
    Version = "2012-10-17"
  })
  tags = {
    Environment = "prod"
  }
}

resource "aws_iam_policy" "ec2_ecr_pull" {
  lifecycle {
    ignore_changes = [tags, tags_all]
  }

  description = "Pull LookDDak application images from the three EC2 ECR repositories"
  name        = "lookddak-prod-ec2-ecr-pull"
  path        = "/"
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
    Environment = "prod"
  }
}

resource "aws_iam_policy" "ec2_parameters_read" {
  lifecycle {
    ignore_changes = [tags, tags_all]
  }

  description = "Read only approved LookDDak production runtime parameters"
  name        = "lookddak-prod-ec2-parameters-read"
  path        = "/"
  policy = jsonencode({
    Statement = [{
      Action   = ["ssm:GetParameter", "ssm:GetParameters"]
      Effect   = "Allow"
      Resource = "arn:aws:ssm:${local.region}:${local.account_id}:parameter/lookddak/prod/*"
      Sid      = "SsmGetLookddakParameters"
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
    Environment = "prod"
  }
}

resource "aws_iam_policy" "ec2_s3_images_rw" {
  lifecycle {
    ignore_changes = [tags, tags_all]
  }

  description = "Read and write objects in the LookDDak production image bucket"
  name        = "lookddak-prod-ec2-s3-images-rw"
  path        = "/"
  policy = jsonencode({
    Statement = [{
      Action   = ["s3:GetBucketLocation", "s3:ListBucket"]
      Effect   = "Allow"
      Resource = "arn:aws:s3:::lookddak-prod-images-${local.account_id}-${local.region}"
      Sid      = "ReadImageBucketMetadata"
      }, {
      Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
      Effect   = "Allow"
      Resource = "arn:aws:s3:::lookddak-prod-images-${local.account_id}-${local.region}/*"
      Sid      = "ReadWriteImageObjects"
    }]
    Version = "2012-10-17"
  })
  tags = {
    Component   = "ec2"
    Environment = "prod"
  }
}

resource "aws_iam_policy" "ec2_ssm_core" {
  lifecycle {
    ignore_changes = [tags, tags_all]
  }

  description = "SSM managed-node and Session Manager access without broad Parameter Store reads"
  name        = "lookddak-prod-ec2-ssm-core"
  path        = "/"
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
    Environment = "prod"
  }
}

resource "aws_iam_role_policy_attachment" "ec2_cloudwatch_logs_write" {
  policy_arn = aws_iam_policy.ec2_cloudwatch_logs_write.arn
  role       = aws_iam_role.ec2.name
}

resource "aws_iam_role_policy_attachment" "ec2_ecr_pull" {
  policy_arn = aws_iam_policy.ec2_ecr_pull.arn
  role       = aws_iam_role.ec2.name
}

resource "aws_iam_role_policy_attachment" "ec2_parameters_read" {
  policy_arn = aws_iam_policy.ec2_parameters_read.arn
  role       = aws_iam_role.ec2.name
}

resource "aws_iam_role_policy_attachment" "ec2_s3_images_rw" {
  policy_arn = aws_iam_policy.ec2_s3_images_rw.arn
  role       = aws_iam_role.ec2.name
}

resource "aws_iam_role_policy_attachment" "ec2_ssm_core" {
  policy_arn = aws_iam_policy.ec2_ssm_core.arn
  role       = aws_iam_role.ec2.name
}

resource "aws_iam_role_policy" "ec2_eventbridge_write" {
  name = "log-eventBridge-write-role"
  policy = jsonencode({
    Statement = [{
      Action   = "events:PutEvents"
      Effect   = "Allow"
      Resource = "arn:aws:events:${local.region}:${local.account_id}:event-bus/default"
    }]
    Version = "2012-10-17"
  })
  role = aws_iam_role.ec2.name
}

resource "aws_iam_role_policy" "ec2_status_log_write" {
  name = "lookddak-alert-status-log"
  policy = jsonencode({
    Statement = [{
      Action   = "logs:PutLogEvents"
      Effect   = "Allow"
      Resource = "arn:aws:logs:${local.region}:${local.account_id}:log-group:/lookddak/prod/status:*"
      Sid      = "ContainerStatusLogs"
    }]
    Version = "2012-10-17"
  })
  role = aws_iam_role.ec2.name
}
