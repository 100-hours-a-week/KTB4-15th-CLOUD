# ---------------------------------------------------------------
# ECS Task Definition 템플릿 저장소 (dev·prod 공용, 키로 구분)
# - Terraform이 서비스별 템플릿(JSON)을 올리고, 앱 레포 CI가 읽어서
#   이미지 digest만 채운 뒤 새 revision을 등록한다.
# - 키: <env>/<version>/<service>.json (예: dev/v2/spring.json)
# - 버전 관리로 템플릿 변경 이력을 보존한다.
# ---------------------------------------------------------------
data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

resource "aws_s3_bucket" "this" {
  bucket = "lookddak-ecs-taskdef-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.region}"

  tags = {
    Component = "ecs-taskdef"
    Purpose   = "ecs-task-definition-templates"
  }
}

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = "Enabled"
  }
}

# 기본 암호화: SSE-S3 (AES256)
resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = false
  }
}

# 퍼블릭 액세스 전부 차단
resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

# ACL 비활성화 (버킷 소유자가 모든 객체 소유)
resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# HTTPS가 아닌 요청 거부
resource "aws_s3_bucket_policy" "this" {
  bucket = aws_s3_bucket.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.this.arn,
          "${aws_s3_bucket.this.arn}/*",
        ]
        Condition = {
          Bool = { "aws:SecureTransport" = "false" }
        }
      },
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.this]
}
