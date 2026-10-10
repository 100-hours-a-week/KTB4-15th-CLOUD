# ---------------------------------------------------------------
# 개발·AI 로컬 테스트용 이미지 버킷 (dev)
# 객체는 7일 후 자동 삭제된다.
# ---------------------------------------------------------------
resource "aws_s3_bucket" "images" {
  bucket = "lookddak-dev-images-686496667254-ap-northeast-2"

  tags = {
    Environment = "dev"
    Purpose     = "ai-local-test"
  }
}

# 기본 암호화: SSE-S3 (AES256)
resource "aws_s3_bucket_server_side_encryption_configuration" "images" {
  bucket = aws_s3_bucket.images.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = false
  }
}

# 퍼블릭 액세스 전부 차단
resource "aws_s3_bucket_public_access_block" "images" {
  bucket = aws_s3_bucket.images.id

  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

# ACL 비활성화 (버킷 소유자가 모든 객체 소유)
resource "aws_s3_bucket_ownership_controls" "images" {
  bucket = aws_s3_bucket.images.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# HTTPS가 아닌 요청 거부
resource "aws_s3_bucket_policy" "images" {
  bucket = aws_s3_bucket.images.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.images.arn,
          "${aws_s3_bucket.images.arn}/*",
        ]
        Condition = {
          Bool = { "aws:SecureTransport" = "false" }
        }
      },
    ]
  })
}

# 테스트 객체는 7일 후 삭제, 미완료 멀티파트 업로드는 1일 후 정리
resource "aws_s3_bucket_lifecycle_configuration" "images" {
  bucket = aws_s3_bucket.images.id

  rule {
    id     = "expire-test-objects-after-7-days"
    status = "Enabled"

    filter {}

    expiration {
      days = 7
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }
}
