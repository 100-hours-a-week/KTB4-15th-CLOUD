# ---------------------------------------------------------------
# FireLens(앱 로그 → Loki) 지원 리소스
# - Fluent Bit init 이미지가 시작할 때 읽을 설정(fluent-bit/loki.conf)과 여러 줄 규칙(fluent-bit/parsers.conf)을 S3에 둔다.
#   (Fargate는 이미지 밖 설정 파일을 직접 못 쓰고, 커스텀 이미지 빌드를 피하려고 init 이미지를 쓴다)
# - Task Role: 설정 파일 읽기 + 기존 앱 로그 그룹 쓰기 (FireLens에서는 ECS가 아니라 Fluent Bit가 CloudWatch에 쓴다)
# - Task SG → Alloy :3500
# ---------------------------------------------------------------
locals {
  fluent_bit_prefix      = "dev/v2/fluent-bit"
  fluent_bit_config_key  = "${local.fluent_bit_prefix}/loki.conf"
  fluent_bit_parsers_key = "${local.fluent_bit_prefix}/parsers.conf"
}

resource "aws_s3_object" "fluent_bit_loki" {
  bucket       = var.taskdef_bucket_name
  key          = local.fluent_bit_config_key
  content      = replace(file("${path.module}/fluent-bit/loki.conf"), "$${LOKI_HOST}", aws_instance.this.private_ip)
  content_type = "text/plain"
}

resource "aws_s3_object" "fluent_bit_parsers" {
  bucket       = var.taskdef_bucket_name
  key          = local.fluent_bit_parsers_key
  content      = file("${path.module}/fluent-bit/parsers.conf")
  content_type = "text/plain"
}

resource "aws_iam_role_policy" "firelens" {
  for_each = var.firelens_task_role_names

  name = "firelens-log-routing"
  role = each.value

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ReadFluentBitConfig"
        Effect   = "Allow"
        Action   = "s3:GetObject"
        Resource = "${var.taskdef_bucket_arn}/${local.fluent_bit_prefix}/*"
      },
      {
        Sid      = "ReadFluentBitConfigBucketLocation"
        Effect   = "Allow"
        Action   = "s3:GetBucketLocation"
        Resource = var.taskdef_bucket_arn
      },
      {
        Sid    = "WriteAppLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams",
        ]
        Resource = "arn:${data.aws_partition.current.partition}:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:log-group:${var.app_log_group_names[each.key]}:*"
      },
    ]
  })
}

resource "aws_vpc_security_group_egress_rule" "app_to_alloy" {
  for_each = var.ecs_task_security_group_ids

  security_group_id            = each.value
  description                  = "FireLens logs to Alloy on the monitoring server"
  ip_protocol                  = "tcp"
  from_port                    = 3500
  to_port                      = 3500
  referenced_security_group_id = aws_security_group.this.id
}

resource "aws_vpc_security_group_ingress_rule" "alloy_from_app" {
  for_each = var.ecs_task_security_group_ids

  security_group_id            = aws_security_group.this.id
  description                  = "FireLens logs from ${each.key} tasks"
  ip_protocol                  = "tcp"
  from_port                    = 3500
  to_port                      = 3500
  referenced_security_group_id = each.value
}
