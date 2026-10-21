# ---------------------------------------------------------------
# Lambda 배포 파일 저장소 (dev)
# - 외부 릴리스 ZIP(예: lambda-promtail)을 sha256 검증 후 버전별 키로 올리고,
#   Lambda는 s3_bucket/s3_key로 참조한다.
# - 키: <함수>/<버전>/<파일> (예: lambda-promtail/v1.0.1/lambda-promtail-v1.0.1.zip)
# - 업그레이드는 새 키로 올린 뒤 Lambda의 s3_key를 바꾸는 PR로 한다.
# ---------------------------------------------------------------
resource "aws_s3_bucket" "lambda_artifacts" {
  bucket = "lookddak-dev-lambda-artifacts-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.region}"

  tags = merge(local.common_tags, {
    Purpose = "lambda-artifacts"
  })
}

resource "aws_s3_bucket_versioning" "lambda_artifacts" {
  bucket = aws_s3_bucket.lambda_artifacts.id

  versioning_configuration {
    status = "Enabled"
  }
}

# 기본 암호화: SSE-S3 (AES256)
resource "aws_s3_bucket_server_side_encryption_configuration" "lambda_artifacts" {
  bucket = aws_s3_bucket.lambda_artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = false
  }
}

# 퍼블릭 액세스 전부 차단
resource "aws_s3_bucket_public_access_block" "lambda_artifacts" {
  bucket = aws_s3_bucket.lambda_artifacts.id

  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

# ACL 비활성화 (버킷 소유자가 모든 객체 소유)
resource "aws_s3_bucket_ownership_controls" "lambda_artifacts" {
  bucket = aws_s3_bucket.lambda_artifacts.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# HTTPS가 아닌 요청 거부
resource "aws_s3_bucket_policy" "lambda_artifacts" {
  bucket = aws_s3_bucket.lambda_artifacts.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.lambda_artifacts.arn,
          "${aws_s3_bucket.lambda_artifacts.arn}/*",
        ]
        Condition = {
          Bool = { "aws:SecureTransport" = "false" }
        }
      },
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.lambda_artifacts]
}
