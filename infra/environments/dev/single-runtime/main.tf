data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

data "aws_region" "current" {}

data "aws_kms_alias" "ssm" {
  name = "alias/aws/ssm"
}

data "aws_s3_bucket" "images" {
  bucket = var.images_bucket_name
}

locals {
  name_prefix = "lookddak-dev-single"
  account_id  = data.aws_caller_identity.current.account_id
  partition   = data.aws_partition.current.partition
  region      = data.aws_region.current.region

  services = toset(["nextjs", "spring", "fastapi", "crawler"])

  # 기존 Dev V2 피팅 비동기 구조를 그대로 사용한다.
  # 이 모듈은 Queue를 조회만 하며 생성·수정·삭제하지 않는다.
  fitting_queues = {
    be-fitting-request  = "lookddak-dev-v2-be-fitting-request"
    ai-fitting-response = "lookddak-dev-v2-ai-fitting-response"
    be-fitting-response = "lookddak-dev-v2-be-fitting-response"
  }

  secret_parameters = toset([
    "mysql/database",
    "mysql/username",
    "mysql/password",
    "postgresql/database",
    "postgresql/username",
    "postgresql/password",
    "spring/jwt-secret",
    "spring/internal-api-key",
    "spring/sentry-dsn",
    "internal/ai-api-key",
    "internal/price-refresh-backend-auth-headers",
    "fastapi/runware-vton-api-key",
    "fastapi/runware-llm-api-key",
    "fastapi/openai-api-key",
    "fastapi/webhook-token",
    "fastapi/virtual-fitting-runware-webhook-url",
    "fastapi/body-image-validation/url",
    "fastapi/body-image-validation/proxy-key",
    "fastapi/body-image-validation/proxy-secret",
    "fastapi/body-image-validation/api-key",
    "fastapi/idm-vton/modal-token-id",
    "fastapi/idm-vton/modal-token-secret",
  ])

  common_tags = {
    Component   = "single-runtime"
    Environment = "dev"
    Purpose     = "docker-compose-runtime"
  }

  ecr_lifecycle_policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images older than 1 day"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 1
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep the 10 most recent tagged images"
        selection = {
          tagStatus      = "tagged"
          tagPatternList = ["*"]
          countType      = "imageCountMoreThan"
          countNumber    = 10
        }
        action = { type = "expire" }
      },
    ]
  })
}

# ---------------------------------------------------------------
# Existing Fitting queues (read only)
# ---------------------------------------------------------------
data "aws_sqs_queue" "fitting_main" {
  for_each = local.fitting_queues

  name = each.value
}

data "aws_sqs_queue" "fitting_dlq" {
  for_each = local.fitting_queues

  name = "${each.value}-dlq"
}

# ---------------------------------------------------------------
# ECR
# ---------------------------------------------------------------
resource "aws_ecr_repository" "service" {
  for_each = local.services

  name                 = "lookddak-dev-${each.key}"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = merge(local.common_tags, {
    Name    = "lookddak-dev-${each.key}"
    Service = each.key
  })
}

resource "aws_ecr_lifecycle_policy" "service" {
  for_each = local.services

  repository = aws_ecr_repository.service[each.key].name
  policy     = local.ecr_lifecycle_policy
}

# ---------------------------------------------------------------
# Database backup bucket
# ---------------------------------------------------------------
resource "aws_s3_bucket" "database_backup" {
  bucket = "${local.name_prefix}-db-backup-${local.account_id}-${local.region}"

  tags = merge(local.common_tags, {
    Name               = "${local.name_prefix}-db-backup"
    DataClassification = "sensitive"
  })

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_public_access_block" "database_backup" {
  bucket = aws_s3_bucket.database_backup.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "database_backup" {
  bucket = aws_s3_bucket.database_backup.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_versioning" "database_backup" {
  bucket = aws_s3_bucket.database_backup.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "database_backup" {
  bucket = aws_s3_bucket.database_backup.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "database_backup" {
  bucket = aws_s3_bucket.database_backup.id

  depends_on = [aws_s3_bucket_versioning.database_backup]

  rule {
    id     = "abort-incomplete-multipart-upload"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }
}

resource "aws_s3_bucket_policy" "database_backup" {
  bucket = aws_s3_bucket.database_backup.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource = [
        aws_s3_bucket.database_backup.arn,
        "${aws_s3_bucket.database_backup.arn}/*",
      ]
      Condition = {
        Bool = {
          "aws:SecureTransport" = "false"
        }
      }
    }]
  })
}

# ---------------------------------------------------------------
# CloudWatch Logs
# ---------------------------------------------------------------
resource "aws_cloudwatch_log_group" "runtime" {
  name              = "/lookddak/dev/single"
  retention_in_days = 14

  tags = merge(local.common_tags, {
    Name = "/lookddak/dev/single"
  })
}

# ---------------------------------------------------------------
# Runtime parameters
# - Secret placeholders are write-only, so secret values do not enter state.
# - Replace them before deploying the Docker Compose workloads.
# ---------------------------------------------------------------
resource "aws_ssm_parameter" "secret" {
  for_each = local.secret_parameters

  name        = "/lookddak/dev/single/${each.key}"
  description = "Single Dev runtime secret: ${each.key}"
  type        = "SecureString"
  key_id      = data.aws_kms_alias.ssm.target_key_arn
  tier        = "Standard"
  data_type   = "text"

  value_wo         = "PENDING_MANUAL_CONFIGURATION"
  value_wo_version = 1

  tags = merge(local.common_tags, {
    Name = "/lookddak/dev/single/${each.key}"
  })

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_ssm_parameter" "runtime" {
  for_each = merge(
    {
      "aws/region"                = local.region
      "s3/images/bucket"          = data.aws_s3_bucket.images.id
      "s3/database-backup/bucket" = aws_s3_bucket.database_backup.id
      "cloudwatch/log-group"      = aws_cloudwatch_log_group.runtime.name
    },
    {
      for name, queue in data.aws_sqs_queue.fitting_main : "sqs/${name}/url" => queue.url
    },
  )

  name  = "/lookddak/dev/single/${each.key}"
  type  = "String"
  value = each.value

  tags = merge(local.common_tags, {
    Name = "/lookddak/dev/single/${each.key}"
  })
}

# ---------------------------------------------------------------
# Minimum EC2 runtime permissions
# ---------------------------------------------------------------
data "aws_iam_policy_document" "instance_runtime" {
  statement {
    sid = "PullServiceImages"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
    ]
    resources = values(aws_ecr_repository.service)[*].arn
  }

  statement {
    sid       = "GetEcrAuthorizationToken"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid = "ListRuntimeBuckets"
    actions = [
      "s3:GetBucketLocation",
      "s3:ListBucket",
    ]
    resources = [
      data.aws_s3_bucket.images.arn,
      aws_s3_bucket.database_backup.arn,
    ]
  }

  statement {
    sid = "UseRuntimeBucketObjects"
    actions = [
      "s3:DeleteObject",
      "s3:GetObject",
      "s3:PutObject",
    ]
    resources = [
      "${data.aws_s3_bucket.images.arn}/*",
      "${aws_s3_bucket.database_backup.arn}/*",
    ]
  }

  statement {
    sid = "UseExistingFittingQueues"
    actions = [
      "sqs:ChangeMessageVisibility",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
      "sqs:GetQueueUrl",
      "sqs:ReceiveMessage",
      "sqs:SendMessage",
    ]
    resources = values(data.aws_sqs_queue.fitting_main)[*].arn
  }

  statement {
    sid = "ReadSingleDevParameters"
    actions = [
      "ssm:GetParameter",
      "ssm:GetParameters",
      "ssm:GetParametersByPath",
    ]
    # GetParametersByPath는 경로 자체 ARN으로 권한을 평가한다.
    resources = [
      "arn:${local.partition}:ssm:${local.region}:${local.account_id}:parameter/lookddak/dev/single",
      "arn:${local.partition}:ssm:${local.region}:${local.account_id}:parameter/lookddak/dev/single/*",
    ]
  }

  statement {
    sid       = "DecryptSingleDevParameters"
    actions   = ["kms:Decrypt"]
    resources = [data.aws_kms_alias.ssm.target_key_arn]

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["ssm.${local.region}.amazonaws.com"]
    }
  }

  statement {
    sid = "WriteRuntimeLogs"
    actions = [
      "logs:CreateLogStream",
      "logs:DescribeLogStreams",
      "logs:PutLogEvents",
    ]
    resources = ["${aws_cloudwatch_log_group.runtime.arn}:*"]
  }
}

resource "aws_iam_role_policy" "instance_runtime" {
  name   = "${local.name_prefix}-runtime"
  role   = var.instance_role_name
  policy = data.aws_iam_policy_document.instance_runtime.json
}
