# ---------------------------------------------------------------
# ECS Task Execution Role policy
# - Uses a project-scoped ECR pattern so a future crawler repository is covered.
# - Parameter Store access is limited to V2 paths and shared V1/V2 dev
#   application parameters.
# - CloudWatch Logs access is limited to the four V2 application log groups.
# - KMS decrypt is limited to the SSM managed key through the SSM service.
# ---------------------------------------------------------------
resource "aws_iam_policy" "task_execution" {
  name        = "lookddak-dev-v2-task-execution"
  description = "Pull LookDDak images and read dev runtime parameters for ECS tasks"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "AuthenticateToEcr"
      Action   = "ecr:GetAuthorizationToken"
      Effect   = "Allow"
      Resource = "*"
      }, {
      Sid      = "PullLookDDakImages"
      Action   = ["ecr:BatchCheckLayerAvailability", "ecr:GetDownloadUrlForLayer", "ecr:BatchGetImage"]
      Effect   = "Allow"
      Resource = local.ecr_repository_arn_pattern
      }, {
      Sid    = "ReadDevParameters"
      Action = ["ssm:GetParameter", "ssm:GetParameters", "ssm:GetParametersByPath"]
      Effect = "Allow"
      Resource = [
        local.dev_v2_parameter_arn_pattern,
        local.dev_fastapi_parameter_arn_pattern,
        local.dev_internal_parameter_arn_pattern,
        local.dev_rds_app_parameter_arn_pattern,
        local.dev_spring_parameter_arn_pattern,
      ]
      }, {
      Sid    = "WriteV2ApplicationLogs"
      Action = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Effect = "Allow"
      Resource = [
        for arn in var.log_group_arns : "${arn}:*"
      ]
      }, {
      Sid      = "DecryptDevParametersViaSsm"
      Action   = "kms:Decrypt"
      Effect   = "Allow"
      Resource = data.aws_kms_alias.ssm.target_key_arn
      Condition = {
        StringEquals = {
          "kms:ViaService" = "ssm.${local.region}.amazonaws.com"
        }
      }
    }]
  })

  tags = {
    Component   = "ecs"
    Environment = "dev"
    Version     = "v2"
  }
}

resource "aws_iam_role_policy_attachment" "task_execution" {
  role       = aws_iam_role.task_execution.name
  policy_arn = aws_iam_policy.task_execution.arn
}

# ---------------------------------------------------------------
# Spring / FastAPI dev S3 read-write policy
# ---------------------------------------------------------------
resource "aws_iam_policy" "task_s3_images_rw" {
  name        = "lookddak-dev-v2-task-s3-images-rw"
  description = "Read and write objects in the LookDDak dev image bucket"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "ReadImageBucketMetadata"
      Action   = ["s3:GetBucketLocation", "s3:ListBucket"]
      Effect   = "Allow"
      Resource = local.dev_image_bucket_arn
      }, {
      Sid      = "ReadWriteImageObjects"
      Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
      Effect   = "Allow"
      Resource = "${local.dev_image_bucket_arn}/*"
    }]
  })

  tags = {
    Component   = "ecs"
    Environment = "dev"
    Version     = "v2"
  }
}

resource "aws_iam_role_policy_attachment" "task_s3_images_rw" {
  for_each = toset(["spring", "fastapi"])

  role       = aws_iam_role.task[each.key].name
  policy_arn = aws_iam_policy.task_s3_images_rw.arn
}

# ---------------------------------------------------------------
# Spring fitting queue policy
# - Publishes fitting requests and consumes final fitting results.
# - DLQ access remains with infrastructure operators.
# ---------------------------------------------------------------
resource "aws_iam_policy" "spring_sqs_fitting" {
  name        = "lookddak-dev-v2-spring-sqs-fitting"
  description = "Publish fitting requests and consume fitting results in V2 dev"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "PublishFittingRequests"
      Action   = "sqs:SendMessage"
      Effect   = "Allow"
      Resource = var.sqs_queue_arns["be-fitting-request"]
      }, {
      Sid = "ConsumeFittingResults"
      Action = [
        "sqs:ReceiveMessage",
        "sqs:DeleteMessage",
        "sqs:ChangeMessageVisibility",
      ]
      Effect   = "Allow"
      Resource = var.sqs_queue_arns["be-fitting-response"]
    }]
  })

  tags = {
    Component   = "sqs"
    Environment = "dev"
    Service     = "spring"
    Version     = "v2"
  }
}

resource "aws_iam_role_policy_attachment" "spring_sqs_fitting" {
  role       = aws_iam_role.task["spring"].name
  policy_arn = aws_iam_policy.spring_sqs_fitting.arn
}

# ---------------------------------------------------------------
# Spring ECS Exec policy
# - SSM Messages channel actions do not support resource-level ARNs.
# ---------------------------------------------------------------
resource "aws_iam_policy" "spring_ecs_exec" {
  name        = "lookddak-dev-v2-spring-ecs-exec"
  description = "Allow the V2 dev Spring task to establish ECS Exec channels"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid = "EcsExecChannels"
      Action = [
        "ssmmessages:CreateControlChannel",
        "ssmmessages:CreateDataChannel",
        "ssmmessages:OpenControlChannel",
        "ssmmessages:OpenDataChannel",
      ]
      Effect   = "Allow"
      Resource = "*"
    }]
  })

  tags = {
    Name        = "lookddak-dev-v2-spring-ecs-exec"
    Environment = "dev"
    Service     = "spring"
    Version     = "v2"
  }
}

resource "aws_iam_role_policy_attachment" "spring_ecs_exec" {
  role       = aws_iam_role.task["spring"].name
  policy_arn = aws_iam_policy.spring_ecs_exec.arn
}

# ---------------------------------------------------------------
# FastAPI fitting queue policy
# - Consumes BE requests, owns the internal AI processing queue,
#   and publishes final results back to BE.
# ---------------------------------------------------------------
resource "aws_iam_policy" "fastapi_sqs_fitting" {
  name        = "lookddak-dev-v2-fastapi-sqs-fitting"
  description = "Consume fitting requests, process AI responses, and publish fitting results in V2 dev"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid = "ConsumeFittingRequests"
      Action = [
        "sqs:ReceiveMessage",
        "sqs:DeleteMessage",
        "sqs:ChangeMessageVisibility",
      ]
      Effect   = "Allow"
      Resource = var.sqs_queue_arns["be-fitting-request"]
      }, {
      Sid = "ProduceAndConsumeAiResponses"
      Action = [
        "sqs:SendMessage",
        "sqs:ReceiveMessage",
        "sqs:DeleteMessage",
        "sqs:ChangeMessageVisibility",
      ]
      Effect   = "Allow"
      Resource = var.sqs_queue_arns["ai-fitting-response"]
      }, {
      Sid      = "PublishFittingResults"
      Action   = "sqs:SendMessage"
      Effect   = "Allow"
      Resource = var.sqs_queue_arns["be-fitting-response"]
    }]
  })

  tags = {
    Component   = "sqs"
    Environment = "dev"
    Service     = "fastapi"
    Version     = "v2"
  }
}

resource "aws_iam_role_policy_attachment" "fastapi_sqs_fitting" {
  role       = aws_iam_role.task["fastapi"].name
  policy_arn = aws_iam_policy.fastapi_sqs_fitting.arn
}

# ---------------------------------------------------------------
# Shared local MQ test policy
# - Covers the complete BE -> AI -> BE flow across the three dev queues.
# - PurgeQueue and all non-SQS permissions are intentionally excluded.
# ---------------------------------------------------------------
resource "aws_iam_policy" "mq_local_test" {
  name        = "lookddak-dev-v2-mq-local-test"
  description = "Test the complete LookDDak V2 dev fitting SQS flow from local environments"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid = "TestFittingMessageFlow"
      Action = [
        "sqs:GetQueueUrl",
        "sqs:GetQueueAttributes",
        "sqs:SendMessage",
        "sqs:ReceiveMessage",
        "sqs:DeleteMessage",
        "sqs:ChangeMessageVisibility",
      ]
      Effect   = "Allow"
      Resource = values(var.sqs_queue_arns)
    }]
  })

  tags = {
    Component   = "sqs"
    Environment = "dev"
    Purpose     = "local-mq-test"
    Version     = "v2"
  }
}

resource "aws_iam_user_policy_attachment" "mq_local_test" {
  user       = aws_iam_user.mq_local_test.name
  policy_arn = aws_iam_policy.mq_local_test.arn
}

# ---------------------------------------------------------------
# Shared test user CloudWatch Logs read policy
# - Preserves the existing V1 dev/prod log viewer scope.
# - Adds every V2 dev application Log Group, including Spring/FastAPI MQ logs.
# - Write, retention, subscription, and deletion permissions are excluded.
# ---------------------------------------------------------------
resource "aws_iam_policy" "mq_local_test_logs_read" {
  name        = "lookddak-dev-v2-mq-local-test-logs-read"
  description = "Read LookDDak dev, V2 dev, and production application logs for MQ testing and troubleshooting"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid = "DiscoverLogGroupsAndQueries"
      Action = [
        "logs:DescribeLogGroups",
        "logs:DescribeQueries",
        "logs:DescribeQueryDefinitions",
      ]
      Effect   = "Allow"
      Resource = "*"
      }, {
      Sid = "ReadLookddakApplicationLogs"
      Action = [
        "logs:DescribeLogStreams",
        "logs:GetLogEvents",
        "logs:FilterLogEvents",
        "logs:GetLogGroupFields",
        "logs:GetLogRecord",
        "logs:GetQueryResults",
        "logs:StartQuery",
        "logs:StopQuery",
        "logs:StartLiveTail",
        "logs:StopLiveTail",
        "logs:ListTagsForResource",
        "logs:ListTagsLogGroup",
      ]
      Effect = "Allow"
      Resource = distinct(flatten([
        for arn in local.shared_test_log_group_arns : [
          arn,
          "${arn}:*",
        ]
      ]))
    }]
  })

  tags = {
    Component   = "cloudwatch-logs"
    Environment = "shared"
    Purpose     = "mq-test-troubleshooting"
    Version     = "v2"
  }
}

resource "aws_iam_user_policy_attachment" "mq_local_test_logs_read" {
  user       = aws_iam_user.mq_local_test.name
  policy_arn = aws_iam_policy.mq_local_test_logs_read.arn
}

# ---------------------------------------------------------------
# Crawler Scheduler policy
# - The crawler Task Definition is created in a later step.
# - PassRole is limited to the crawler Task Role and Execution Role.
# ---------------------------------------------------------------
resource "aws_iam_policy" "crawler_scheduler" {
  name        = "lookddak-dev-v2-crawler-scheduler"
  description = "Run the LookDDak dev V2 crawler task on the designated ECS cluster"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "RunCrawlerTask"
      Action   = "ecs:RunTask"
      Effect   = "Allow"
      Resource = local.crawler_task_definition_arn_pattern
      Condition = {
        ArnEquals = {
          "ecs:cluster" = var.ecs_cluster_arn
        }
      }
      }, {
      Sid    = "PassCrawlerTaskRoles"
      Action = "iam:PassRole"
      Effect = "Allow"
      Resource = [
        aws_iam_role.task["crawler"].arn,
        aws_iam_role.task_execution.arn,
      ]
      Condition = {
        StringEquals = {
          "iam:PassedToService" = "ecs-tasks.amazonaws.com"
        }
      }
    }]
  })

  tags = {
    Component   = "scheduler"
    Environment = "dev"
    Service     = "crawler"
    Version     = "v2"
  }
}

resource "aws_iam_role_policy_attachment" "crawler_scheduler" {
  role       = aws_iam_role.crawler_scheduler.name
  policy_arn = aws_iam_policy.crawler_scheduler.arn
}
