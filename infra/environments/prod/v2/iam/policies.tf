resource "aws_iam_policy" "task_execution" {
  name        = "lookddak-prod-v2-task-execution"
  description = "Pull LookDDak images and read prod runtime parameters for ECS tasks"
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
      Resource = var.ecr_repository_arns
      }, {
      Sid    = "ReadProdParameters"
      Action = ["ssm:GetParameter", "ssm:GetParameters", "ssm:GetParametersByPath"]
      Effect = "Allow"
      Resource = [
        local.prod_v2_parameter_arn_pattern,
        local.prod_fastapi_parameter_arn_pattern,
        local.prod_internal_parameter_arn_pattern,
        local.prod_spring_parameter_arn_pattern,
      ]
      }, {
      Sid    = "WriteV2ApplicationLogs"
      Action = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Effect = "Allow"
      Resource = [
        for arn in var.log_group_arns : "${arn}:*"
      ]
      }, {
      Sid      = "DecryptProdParametersViaSsm"
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
    Environment = "prod"
    Version     = "v2"
  }
}

resource "aws_iam_role_policy_attachment" "task_execution" {
  role       = aws_iam_role.task_execution.name
  policy_arn = aws_iam_policy.task_execution.arn
}

resource "aws_iam_policy" "task_s3_images_rw" {
  name        = "lookddak-prod-v2-task-s3-images-rw"
  description = "Read and write objects in the LookDDak prod image bucket"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "ReadImageBucketMetadata"
      Action   = ["s3:GetBucketLocation", "s3:ListBucket"]
      Effect   = "Allow"
      Resource = local.prod_image_bucket_arn
      }, {
      Sid      = "ReadWriteImageObjects"
      Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
      Effect   = "Allow"
      Resource = "${local.prod_image_bucket_arn}/*"
    }]
  })

  tags = {
    Component   = "ecs"
    Environment = "prod"
    Version     = "v2"
  }
}

resource "aws_iam_role_policy_attachment" "task_s3_images_rw" {
  for_each = toset(["spring", "fastapi"])

  role       = aws_iam_role.task[each.key].name
  policy_arn = aws_iam_policy.task_s3_images_rw.arn
}

resource "aws_iam_policy" "spring_sqs_fitting" {
  name        = "lookddak-prod-v2-spring-sqs-fitting"
  description = "Publish fitting requests and consume fitting results in V2 prod"
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
    Environment = "prod"
    Service     = "spring"
    Version     = "v2"
  }
}

resource "aws_iam_role_policy_attachment" "spring_sqs_fitting" {
  role       = aws_iam_role.task["spring"].name
  policy_arn = aws_iam_policy.spring_sqs_fitting.arn
}

resource "aws_iam_policy" "spring_ecs_exec" {
  name        = "lookddak-prod-v2-spring-ecs-exec"
  description = "Allow the V2 prod Spring task to establish ECS Exec channels"
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
    Name        = "lookddak-prod-v2-spring-ecs-exec"
    Environment = "prod"
    Service     = "spring"
    Version     = "v2"
  }
}

resource "aws_iam_role_policy_attachment" "spring_ecs_exec" {
  role       = aws_iam_role.task["spring"].name
  policy_arn = aws_iam_policy.spring_ecs_exec.arn
}

resource "aws_iam_policy" "fastapi_sqs_fitting" {
  name        = "lookddak-prod-v2-fastapi-sqs-fitting"
  description = "Consume fitting requests, process AI responses, and publish fitting results in V2 prod"
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
    Environment = "prod"
    Service     = "fastapi"
    Version     = "v2"
  }
}

resource "aws_iam_role_policy_attachment" "fastapi_sqs_fitting" {
  role       = aws_iam_role.task["fastapi"].name
  policy_arn = aws_iam_policy.fastapi_sqs_fitting.arn
}

resource "aws_iam_policy" "crawler_scheduler" {
  name        = "lookddak-prod-v2-crawler-scheduler"
  description = "Run the LookDDak prod V2 crawler task on the designated ECS cluster"
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
    Environment = "prod"
    Service     = "crawler"
    Version     = "v2"
  }
}

resource "aws_iam_role_policy_attachment" "crawler_scheduler" {
  role       = aws_iam_role.crawler_scheduler.name
  policy_arn = aws_iam_policy.crawler_scheduler.arn
}
