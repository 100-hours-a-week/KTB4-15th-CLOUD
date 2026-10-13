# ---------------------------------------------------------------
# 사용자 사진·피팅 결과 이미지 버킷 (prod)
# V1 EC2가 사용 중이며 V2 전환 후에도 데이터를 그대로 이어서 사용한다.
# ---------------------------------------------------------------
resource "aws_s3_bucket" "images" {
  bucket = "lookddak-prod-images-686496667254-ap-northeast-2"

  tags = {
    Name        = "lookddak-prod-images"
    Environment = "prod"
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

# ---------------------------------------------------------------
# PostgreSQL 백업 전용 버킷 (prod)
# 서비스 이미지와 수명 주기 및 접근 주체가 달라 별도로 관리한다.
# ---------------------------------------------------------------
resource "aws_kms_key" "postgresql_backup" {
  description             = "KMS key for lookddak prod PostgreSQL backups"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Name        = "lookddak-prod-postgresql-backup"
    Environment = "prod"
    Purpose     = "postgresql-backup"
  }
}

resource "aws_kms_alias" "postgresql_backup" {
  name          = "alias/lookddak-prod-postgresql-backup"
  target_key_id = aws_kms_key.postgresql_backup.key_id
}

resource "aws_s3_bucket" "postgresql_backup" {
  bucket = "lookddak-prod-db-backup-686496667254-ap-northeast-2"

  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Name               = "lookddak-prod-db-backup"
    Environment        = "prod"
    Purpose            = "postgresql-backup"
    DataClassification = "sensitive"
  }
}

resource "aws_s3_bucket_public_access_block" "postgresql_backup" {
  bucket = aws_s3_bucket.postgresql_backup.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "postgresql_backup" {
  bucket = aws_s3_bucket.postgresql_backup.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_versioning" "postgresql_backup" {
  bucket = aws_s3_bucket.postgresql_backup.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "postgresql_backup" {
  bucket = aws_s3_bucket.postgresql_backup.id

  rule {
    bucket_key_enabled = true

    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.postgresql_backup.arn
      sse_algorithm     = "aws:kms"
    }
  }
}

# 완료되지 않은 멀티파트 업로드만 정리한다.
# 백업 파일의 보존 기간은 운영 정책 확정 후 별도로 추가한다.
resource "aws_s3_bucket_lifecycle_configuration" "postgresql_backup" {
  bucket = aws_s3_bucket.postgresql_backup.id

  depends_on = [aws_s3_bucket_versioning.postgresql_backup]

  rule {
    id     = "abort-incomplete-multipart-upload"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }
}

resource "aws_s3_bucket_policy" "postgresql_backup" {
  bucket = aws_s3_bucket.postgresql_backup.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.postgresql_backup.arn,
          "${aws_s3_bucket.postgresql_backup.arn}/*",
        ]
        Condition = {
          Bool = { "aws:SecureTransport" = "false" }
        }
      },
    ]
  })
}
