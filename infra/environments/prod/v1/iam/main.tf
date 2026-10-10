# V1 IAM resources imported from the existing AWS configuration.
# Keep this file aligned with the current configuration during the baseline import.

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
      Resource = ["arn:aws:ssm:ap-northeast-2::document/AWS-RunShellScript", "arn:aws:ec2:ap-northeast-2:686496667254:instance/i-0b4d0ff11e09efb6a"]
      Sid      = "SsmSend"
      }, {
      Action   = "ssm:GetCommandInvocation"
      Effect   = "Allow"
      Resource = "*"
      Sid      = "SsmGetResult"
    }]
    Version = "2012-10-17"
  })
  role = aws_iam_role.ai_deploy.name
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
      Resource = ["arn:aws:ssm:ap-northeast-2::document/AWS-RunShellScript", "arn:aws:ec2:ap-northeast-2:686496667254:instance/i-0b4d0ff11e09efb6a"]
      Sid      = "SsmSend"
      }, {
      Action   = "ssm:GetCommandInvocation"
      Effect   = "Allow"
      Resource = "*"
      Sid      = "SsmGetResult"
    }]
    Version = "2012-10-17"
  })
  role = aws_iam_role.be_deploy.name
}

resource "aws_iam_role_policy_attachment" "eventbridge_aws_health" {
  policy_arn = aws_iam_policy.eventbridge_aws_health.arn
  role       = aws_iam_role.eventbridge_aws_health.name
}

resource "aws_iam_policy" "eventbridge_alarm_state_change" {
  lifecycle {
    ignore_changes = [tags, tags_all]
  }

  name = "Amazon_EventBridge_Invoke_Sqs_1504746143"
  path = "/service-role/"
  policy = jsonencode({
    Statement = [{
      Action   = ["sqs:SendMessage"]
      Effect   = "Allow"
      Resource = ["arn:aws:sqs:ap-northeast-2:686496667254:lookddak-alert-queue"]
    }]
    Version = "2012-10-17"
  })
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
      Resource = ["arn:aws:logs:ap-northeast-2:686496667254:log-group:/lookddak/prod/nginx:log-stream:*", "arn:aws:logs:ap-northeast-2:686496667254:log-group:/lookddak/prod/nextjs:log-stream:*", "arn:aws:logs:ap-northeast-2:686496667254:log-group:/lookddak/prod/spring:log-stream:*", "arn:aws:logs:ap-northeast-2:686496667254:log-group:/lookddak/prod/fastapi:log-stream:*", "arn:aws:logs:ap-northeast-2:686496667254:log-group:/lookddak/prod/postgresql:log-stream:*"]
      Sid      = "WriteLookDDakContainerLogs"
    }]
    Version = "2012-10-17"
  })
  tags = {
    Environment = "prod"
  }
}

resource "aws_iam_role_policy_attachment" "ec2_parameters_read" {
  policy_arn = aws_iam_policy.ec2_parameters_read.arn
  role       = aws_iam_role.ec2.name
}

resource "aws_iam_role" "eventbridge_docker_events" {
  lifecycle {
    ignore_changes = [tags, tags_all]
  }

  assume_role_policy = jsonencode({
    Statement = [{
      Action = "sts:AssumeRole"
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = "686496667254"
          "aws:SourceArn"     = "arn:aws:events:ap-northeast-2:686496667254:rule/lookddak-docker-events"
        }
      }
      Effect = "Allow"
      Principal = {
        Service = "events.amazonaws.com"
      }
      Sid = "TrustEventBridgeService"
    }]
    Version = "2012-10-17"
  })
  name = "Amazon_EventBridge_Invoke_Sqs_2071571937"
  path = "/service-role/"
  tags = {}
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

resource "aws_iam_role_policy_attachment" "eventbridge_rds_events" {
  policy_arn = aws_iam_policy.eventbridge_rds_events.arn
  role       = aws_iam_role.eventbridge_rds_events.name
}

resource "aws_iam_role_policy_attachment" "discord_alert_sqs" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaSQSQueueExecutionRole"
  role       = aws_iam_role.discord_alert.name
}

resource "aws_iam_role" "eventbridge_alarm_state_change" {
  lifecycle {
    ignore_changes = [tags, tags_all]
  }

  assume_role_policy = jsonencode({
    Statement = [{
      Action = "sts:AssumeRole"
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = "686496667254"
          "aws:SourceArn"     = "arn:aws:events:ap-northeast-2:686496667254:rule/lookddak-alarm-state-change"
        }
      }
      Effect = "Allow"
      Principal = {
        Service = "events.amazonaws.com"
      }
      Sid = "TrustEventBridgeService"
    }]
    Version = "2012-10-17"
  })
  name = "Amazon_EventBridge_Invoke_Sqs_1504746143"
  path = "/service-role/"
  tags = {}
}

resource "aws_iam_role_policy" "ec2_eventbridge_write" {
  name = "log-eventBridge-write-role"
  policy = jsonencode({
    Statement = [{
      Action   = "events:PutEvents"
      Effect   = "Allow"
      Resource = "arn:aws:events:ap-northeast-2:686496667254:event-bus/default"
    }]
    Version = "2012-10-17"
  })
  role = aws_iam_role.ec2.name
}

resource "aws_iam_role" "eventbridge_aws_health" {
  lifecycle {
    ignore_changes = [tags, tags_all]
  }

  assume_role_policy = jsonencode({
    Statement = [{
      Action = "sts:AssumeRole"
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = "686496667254"
          "aws:SourceArn"     = "arn:aws:events:ap-northeast-2:686496667254:rule/lookddak-aws-health"
        }
      }
      Effect = "Allow"
      Principal = {
        Service = "events.amazonaws.com"
      }
      Sid = "TrustEventBridgeService"
    }]
    Version = "2012-10-17"
  })
  name = "Amazon_EventBridge_Invoke_Sqs_1568336830"
  path = "/service-role/"
  tags = {}
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
        Federated = "arn:aws:iam::686496667254:oidc-provider/token.actions.githubusercontent.com"
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
        Federated = "arn:aws:iam::686496667254:oidc-provider/token.actions.githubusercontent.com"
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

resource "aws_iam_role_policy_attachment" "eventbridge_alarm_state_change" {
  policy_arn = aws_iam_policy.eventbridge_alarm_state_change.arn
  role       = aws_iam_role.eventbridge_alarm_state_change.name
}

resource "aws_iam_role_policy_attachment" "ec2_ecr_pull" {
  policy_arn = aws_iam_policy.ec2_ecr_pull.arn
  role       = aws_iam_role.ec2.name
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

resource "aws_iam_policy" "eventbridge_ec2_state_change" {
  lifecycle {
    ignore_changes = [tags, tags_all]
  }

  name = "Amazon_EventBridge_Invoke_Sqs_1541928649"
  path = "/service-role/"
  policy = jsonencode({
    Statement = [{
      Action   = ["sqs:SendMessage"]
      Effect   = "Allow"
      Resource = ["arn:aws:sqs:ap-northeast-2:686496667254:lookddak-alert-queue"]
    }]
    Version = "2012-10-17"
  })
  tags = {}
}

resource "aws_iam_role" "discord_alert" {
  lifecycle {
    ignore_changes = [tags, tags_all]
  }

  assume_role_policy = jsonencode({
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
    Version = "2012-10-17"
  })
  name = "lookddak-discord-alert-role-pl51jpue"
  path = "/service-role/"
  tags = {}
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

resource "aws_iam_role_policy_attachment" "ec2_cloudwatch_logs_write" {
  policy_arn = aws_iam_policy.ec2_cloudwatch_logs_write.arn
  role       = aws_iam_role.ec2.name
}

resource "aws_iam_role_policy_attachment" "discord_alert_logs" {
  policy_arn = aws_iam_policy.discord_alert_logs.arn
  role       = aws_iam_role.discord_alert.name
}

resource "aws_iam_role_policy_attachment" "ec2_s3_images_rw" {
  policy_arn = aws_iam_policy.ec2_s3_images_rw.arn
  role       = aws_iam_role.ec2.name
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
      Resource = ["arn:aws:ssm:ap-northeast-2::document/AWS-RunShellScript", "arn:aws:ec2:ap-northeast-2:686496667254:instance/i-0b4d0ff11e09efb6a"]
      Sid      = "SsmSend"
      }, {
      Action   = "ssm:GetCommandInvocation"
      Effect   = "Allow"
      Resource = "*"
      Sid      = "SsmGetResult"
    }]
    Version = "2012-10-17"
  })
  role = aws_iam_role.fe_deploy.name
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
      Resource = "arn:aws:s3:::lookddak-prod-images-686496667254-ap-northeast-2"
      Sid      = "ReadImageBucketMetadata"
      }, {
      Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
      Effect   = "Allow"
      Resource = "arn:aws:s3:::lookddak-prod-images-686496667254-ap-northeast-2/*"
      Sid      = "ReadWriteImageObjects"
    }]
    Version = "2012-10-17"
  })
  tags = {
    Component   = "ec2"
    Environment = "prod"
  }
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

resource "aws_iam_role_policy_attachment" "ec2_ssm_core" {
  policy_arn = aws_iam_policy.ec2_ssm_core.arn
  role       = aws_iam_role.ec2.name
}

resource "aws_iam_role_policy_attachment" "eventbridge_ec2_state_change" {
  policy_arn = aws_iam_policy.eventbridge_ec2_state_change.arn
  role       = aws_iam_role.eventbridge_ec2_state_change.name
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
        Federated = "arn:aws:iam::686496667254:oidc-provider/token.actions.githubusercontent.com"
      }
    }]
    Version = "2012-10-17"
  })
  name = "be-cd-deploy-role"
  path = "/"
  tags = {}
}

resource "aws_iam_policy" "eventbridge_rds_events" {
  lifecycle {
    ignore_changes = [tags, tags_all]
  }

  name = "Amazon_EventBridge_Invoke_Sqs_533425366"
  path = "/service-role/"
  policy = jsonencode({
    Statement = [{
      Action   = ["sqs:SendMessage"]
      Effect   = "Allow"
      Resource = ["arn:aws:sqs:ap-northeast-2:686496667254:lookddak-alert-queue"]
    }]
    Version = "2012-10-17"
  })
  tags = {}
}

resource "aws_iam_role" "eventbridge_rds_events" {
  lifecycle {
    ignore_changes = [tags, tags_all]
  }

  assume_role_policy = jsonencode({
    Statement = [{
      Action = "sts:AssumeRole"
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = "686496667254"
          "aws:SourceArn"     = "arn:aws:events:ap-northeast-2:686496667254:rule/lookddak-rds-events"
        }
      }
      Effect = "Allow"
      Principal = {
        Service = "events.amazonaws.com"
      }
      Sid = "TrustEventBridgeService"
    }]
    Version = "2012-10-17"
  })
  name = "Amazon_EventBridge_Invoke_Sqs_533425366"
  path = "/service-role/"
  tags = {}
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
      Resource = "arn:aws:ssm:ap-northeast-2:686496667254:parameter/lookddak/prod/*"
      Sid      = "SsmGetLookddakParameters"
      }, {
      Action = "kms:Decrypt"
      Condition = {
        StringEquals = {
          "kms:ViaService" = "ssm.ap-northeast-2.amazonaws.com"
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

resource "aws_iam_role_policy" "discord_alert_status_logs_read" {
  name = "LamdaRole"
  policy = jsonencode({
    Statement = [{
      Action   = "logs:GetLogEvents"
      Effect   = "Allow"
      Resource = "arn:aws:logs:ap-northeast-2:686496667254:log-group:/lookddak/prod/status:*"
    }]
    Version = "2012-10-17"
  })
  role = aws_iam_role.discord_alert.name
}

resource "aws_iam_policy" "eventbridge_docker_events" {
  lifecycle {
    ignore_changes = [tags, tags_all]
  }

  name = "Amazon_EventBridge_Invoke_Sqs_2071571937"
  path = "/service-role/"
  policy = jsonencode({
    Statement = [{
      Action   = ["sqs:SendMessage"]
      Effect   = "Allow"
      Resource = ["arn:aws:sqs:ap-northeast-2:686496667254:lookddak-alert-queue"]
    }]
    Version = "2012-10-17"
  })
  tags = {}
}

resource "aws_iam_role_policy" "ec2_status_log_write" {
  name = "lookddak-alert-status-log"
  policy = jsonencode({
    Statement = [{
      Action   = "logs:PutLogEvents"
      Effect   = "Allow"
      Resource = "arn:aws:logs:ap-northeast-2:686496667254:log-group:/lookddak/prod/status:*"
      Sid      = "ContainerStatusLogs"
    }]
    Version = "2012-10-17"
  })
  role = aws_iam_role.ec2.name
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
        Federated = "arn:aws:iam::686496667254:oidc-provider/token.actions.githubusercontent.com"
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

resource "aws_iam_role_policy_attachment" "eventbridge_docker_events" {
  policy_arn = aws_iam_policy.eventbridge_docker_events.arn
  role       = aws_iam_role.eventbridge_docker_events.name
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
      Resource = "arn:aws:ssm:ap-northeast-2:686496667254:parameter/lookddak/prod/cicd/sentry/auth-token"
      Sid      = "SsmReadSentryAuthToken"
    }]
    Version = "2012-10-17"
  })
  role = aws_iam_role.fe_build.name
}

resource "aws_iam_role" "eventbridge_ec2_state_change" {
  lifecycle {
    ignore_changes = [tags, tags_all]
  }

  assume_role_policy = jsonencode({
    Statement = [{
      Action = "sts:AssumeRole"
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = "686496667254"
          "aws:SourceArn"     = "arn:aws:events:ap-northeast-2:686496667254:rule/lookddak-ec2-state-change"
        }
      }
      Effect = "Allow"
      Principal = {
        Service = "events.amazonaws.com"
      }
      Sid = "TrustEventBridgeService"
    }]
    Version = "2012-10-17"
  })
  name = "Amazon_EventBridge_Invoke_Sqs_1541928649"
  path = "/service-role/"
  tags = {}
}

resource "aws_iam_policy" "eventbridge_aws_health" {
  lifecycle {
    ignore_changes = [tags, tags_all]
  }

  name = "Amazon_EventBridge_Invoke_Sqs_1568336830"
  path = "/service-role/"
  policy = jsonencode({
    Statement = [{
      Action   = ["sqs:SendMessage"]
      Effect   = "Allow"
      Resource = ["arn:aws:sqs:ap-northeast-2:686496667254:lookddak-alert-queue"]
    }]
    Version = "2012-10-17"
  })
  tags = {}
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
        Federated = "arn:aws:iam::686496667254:oidc-provider/token.actions.githubusercontent.com"
      }
    }]
    Version = "2012-10-17"
  })
  name = "fe-cd-deploy-role"
  path = "/"
  tags = {}
}

resource "aws_iam_policy" "discord_alert_logs" {
  lifecycle {
    ignore_changes = [tags, tags_all]
  }

  name = "AWSLambdaBasicExecutionRole-95b4d8dc-ae9a-4906-bfae-0a3702a265cf"
  path = "/service-role/"
  policy = jsonencode({
    Statement = [{
      Action   = "logs:CreateLogGroup"
      Effect   = "Allow"
      Resource = "arn:aws:logs:ap-northeast-2:686496667254:*"
      }, {
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Effect   = "Allow"
      Resource = ["arn:aws:logs:ap-northeast-2:686496667254:log-group:/aws/lambda/lookddak-discord-alert:*"]
    }]
    Version = "2012-10-17"
  })
  tags = {}
}

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
        Federated = "arn:aws:iam::686496667254:oidc-provider/token.actions.githubusercontent.com"
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
