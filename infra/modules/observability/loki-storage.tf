# ---------------------------------------------------------------
# Loki 저장소 (S3)
# - 로그 청크와 색인을 S3에 둔다. Monitoring EC2를 교체해도 로그가 남는다.
# - 보존(7일)은 Loki compactor가 지운다. 아래 수명 주기는 compactor가 놓친 객체를 지우는 안전장치.
# - 버킷 이름에 계정 ID가 들어가서 Loki 설정 파일에는 쓰지 않는다. 서버 .env의 LOKI_S3_BUCKET으로 넣는다.
# - 트래픽은 S3 Gateway Endpoint(dev/v2/network)를 탄다.
# ---------------------------------------------------------------
resource "aws_s3_bucket" "loki" {
  bucket = "lookddak-${var.environment}-loki-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.region}"

  tags = merge(local.common_tags, {
    Purpose = "loki-chunks-index"
  })
}

resource "aws_s3_bucket_server_side_encryption_configuration" "loki" {
  bucket = aws_s3_bucket.loki.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = false
  }
}

resource "aws_s3_bucket_public_access_block" "loki" {
  bucket = aws_s3_bucket.loki.id

  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "loki" {
  bucket = aws_s3_bucket.loki.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "loki" {
  bucket = aws_s3_bucket.loki.id

  rule {
    id     = "safety-expire-30d"
    status = "Enabled"

    filter {}

    expiration {
      days = 30
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }
}

resource "aws_s3_bucket_policy" "loki" {
  bucket = aws_s3_bucket.loki.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.loki.arn,
          "${aws_s3_bucket.loki.arn}/*",
        ]
        Condition = {
          Bool = { "aws:SecureTransport" = "false" }
        }
      },
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.loki]
}

# Loki 컨테이너는 EC2 인스턴스 역할(IMDSv2, hop limit 2)로 S3에 접근한다.
resource "aws_iam_role_policy" "loki_storage" {
  name = "loki-storage"
  role = aws_iam_role.instance.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ListLokiBucket"
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = aws_s3_bucket.loki.arn
      },
      {
        Sid      = "ReadWriteLokiObjects"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = "${aws_s3_bucket.loki.arn}/*"
      },
    ]
  })
}
