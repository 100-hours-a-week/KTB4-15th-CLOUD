# ---------------------------------------------------------------
# dev ALB 액세스 로그: ALB → S3 → (객체 생성 이벤트) → lambda-promtail → Loki
# - CloudWatch vended logs도 5분 묶음 전달이라 실측 지연이 S3와 같았다(18초~5분).
#   prod와 같은 S3 방식으로 맞추고 CloudWatch 수집 비용을 없앤다.
# - lambda-promtail은 로그 줄의 요청 시각을 Loki 타임스탬프로 쓴다.
# - 레이블: lambda-promtail이 __aws_log_type="s3_lb"를 붙이고, Alloy가 source="alb"로 바꾼다.
# - 객체 키: alb/AWSLogs/<계정>/elasticloadbalancing/<리전>/yyyy/mm/dd/*.log.gz
# - Loki 보존이 7일이라 S3도 7일 뒤 삭제한다.
# ---------------------------------------------------------------
locals {
  alb_logs_prefix = "alb/AWSLogs/${data.aws_caller_identity.current.account_id}/"
}

data "aws_elb_service_account" "current" {}

resource "aws_s3_bucket" "alb_logs" {
  bucket = "lookddak-${var.environment}-alb-logs-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.region}"

  tags = merge(local.common_tags, {
    Purpose = "alb-access-logs"
  })
}

# ALB 액세스 로그는 SSE-S3만 지원한다
resource "aws_s3_bucket_server_side_encryption_configuration" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = false
  }
}

resource "aws_s3_bucket_public_access_block" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  rule {
    id     = "expire-7d"
    status = "Enabled"

    filter {}

    expiration {
      days = 7
    }
  }
}

# 서울 리전 ELB 계정이 alb/ 아래에만 쓸 수 있게 허용 + HTTPS가 아닌 요청 거부
# ALB의 access_logs는 이 정책을 확인한 뒤에야 켜진다 (출력이 정책을 거쳐 전달되는 이유)
resource "aws_s3_bucket_policy" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowELBLogDelivery"
        Effect    = "Allow"
        Principal = { AWS = data.aws_elb_service_account.current.arn }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.alb_logs.arn}/${local.alb_logs_prefix}*"
      },
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.alb_logs.arn,
          "${aws_s3_bucket.alb_logs.arn}/*",
        ]
        Condition = {
          Bool = { "aws:SecureTransport" = "false" }
        }
      },
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.alb_logs]
}

# --- 객체 생성 → lambda-promtail ---
resource "aws_iam_role_policy" "lambda_promtail_alb_logs" {
  name = "alb-logs-read"
  role = aws_iam_role.lambda_promtail.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "s3:GetObject"
      Resource = "${aws_s3_bucket.alb_logs.arn}/${local.alb_logs_prefix}*"
    }]
  })
}

resource "aws_lambda_permission" "s3_alb_logs" {
  statement_id   = "AllowS3AlbLogs"
  action         = "lambda:InvokeFunction"
  function_name  = aws_lambda_function.lambda_promtail.function_name
  principal      = "s3.amazonaws.com"
  source_arn     = aws_s3_bucket.alb_logs.arn
  source_account = data.aws_caller_identity.current.account_id
}

# 로그 파일(.log.gz)만 보낸다. 활성화 때 생기는 ELBAccessLogTestFile은 제외된다.
resource "aws_s3_bucket_notification" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.lambda_promtail.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = local.alb_logs_prefix
    filter_suffix       = ".log.gz"
  }

  depends_on = [
    aws_lambda_permission.s3_alb_logs,
    aws_iam_role_policy.lambda_promtail_alb_logs,
  ]
}
