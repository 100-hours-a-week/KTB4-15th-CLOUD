# ---------------------------------------------------------------
# ECS Task Execution Role policy
# - Uses a project-scoped ECR pattern so a future crawler repository is covered.
# - Parameter Store access is limited to /lookddak/dev/*.
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
      Sid      = "ReadDevParameters"
      Action   = ["ssm:GetParameter", "ssm:GetParameters", "ssm:GetParametersByPath"]
      Effect   = "Allow"
      Resource = local.dev_parameter_arn_pattern
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
