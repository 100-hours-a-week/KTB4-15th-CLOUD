# ---------------------------------------------------------------
# 트레이스 (Tempo)
# - 앱(OTel 에이전트·SDK) → Alloy :4317 (OTLP gRPC) / :4318 (OTLP HTTP) → Tempo(Monitoring EC2 컨테이너) → S3
# - 트레이스 블록을 S3에 둔다. 보존(7일)은 Tempo가 지운다. 아래 수명 주기는 놓친 객체용 안전장치.
# - 버킷 이름에 계정 ID가 들어가서 Tempo 설정 파일에는 쓰지 않는다. 서버 .env의 TEMPO_S3_BUCKET으로 넣는다.
# - 트래픽은 S3 Gateway Endpoint(dev/v2/network)를 탄다.
# ---------------------------------------------------------------
resource "aws_s3_bucket" "tempo" {
  bucket = "lookddak-dev-tempo-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.region}"

  tags = merge(local.common_tags, {
    Purpose = "tempo-traces"
  })
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tempo" {
  bucket = aws_s3_bucket.tempo.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = false
  }
}

resource "aws_s3_bucket_public_access_block" "tempo" {
  bucket = aws_s3_bucket.tempo.id

  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "tempo" {
  bucket = aws_s3_bucket.tempo.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "tempo" {
  bucket = aws_s3_bucket.tempo.id

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

resource "aws_s3_bucket_policy" "tempo" {
  bucket = aws_s3_bucket.tempo.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.tempo.arn,
          "${aws_s3_bucket.tempo.arn}/*",
        ]
        Condition = {
          Bool = { "aws:SecureTransport" = "false" }
        }
      },
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.tempo]
}

# Tempo 컨테이너는 EC2 인스턴스 역할(IMDSv2, hop limit 2)로 S3에 접근한다.
resource "aws_iam_role_policy" "tempo_storage" {
  name = "tempo-storage"
  role = aws_iam_role.instance.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ListTempoBucket"
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = aws_s3_bucket.tempo.arn
      },
      {
        Sid    = "ReadWriteTempoObjects"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:GetObjectTagging",
          "s3:PutObjectTagging",
        ]
        Resource = "${aws_s3_bucket.tempo.arn}/*"
      },
    ]
  })
}

# 앱 Task → Alloy OTLP 트레이스 (4317 gRPC: spring, 4318 HTTP: nextjs·fastapi). 로그(3500)와 같은 방식
resource "aws_vpc_security_group_egress_rule" "app_to_alloy_otlp" {
  for_each = var.ecs_task_security_group_ids

  security_group_id            = each.value
  description                  = "OTLP traces to Alloy on the monitoring server"
  ip_protocol                  = "tcp"
  from_port                    = 4317
  to_port                      = 4318
  referenced_security_group_id = aws_security_group.this.id
}

resource "aws_vpc_security_group_ingress_rule" "alloy_otlp_from_app" {
  for_each = var.ecs_task_security_group_ids

  security_group_id            = aws_security_group.this.id
  description                  = "OTLP traces from ${each.key} tasks"
  ip_protocol                  = "tcp"
  from_port                    = 4317
  to_port                      = 4318
  referenced_security_group_id = each.value
}
