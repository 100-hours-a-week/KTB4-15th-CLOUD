# ---------------------------------------------------------------
# lambda-promtail: CloudWatch Logs 구독·S3(ALB 로그) → Alloy(:3500) → Loki
# - Grafana 공식 릴리스 ZIP을 sha256 검증 후 lambda-artifacts 버킷에 올려 참조한다.
#   (lambda-promtail-v1.0.1.zip, sha256 2a436a30772ac638f715dd240784f787b9f0c745ba292a49cd23d132c477fd13)
# - VPC 안에서 Monitoring EC2의 고정 IP로 보낸다.
#   ALB 로그 파일은 S3에서 읽는다(NAT 경유, 443만 S3 IP 대역으로 허용).
# - CloudWatch Logs 구독·S3 이벤트는 비동기 호출이다. 실패하면 2번 재시도하고,
#   끝내 실패한 이벤트는 SQS(failed)로 보낸다. 설정하지 않으면 조용히 버려진다.
# - PRINT_LOG_LINE=false: 기본값(true)이면 받은 로그를 자기 로그에 다시 찍어
#   CloudWatch 수집 비용이 두 배가 된다.
# - log_group·source 레이블은 Alloy(loki.source.api relabel_rules)에서 만든다.
#   lambda-promtail은 __aws_cloudwatch_log_group 등 __ 레이블을 그대로 보내고,
#   Alloy가 이를 변환한 뒤 __ 레이블을 버린다.
# ---------------------------------------------------------------
locals {
  lambda_promtail_name    = "lookddak-${var.environment}-lambda-promtail"
  lambda_promtail_version = "v1.0.1"
  lambda_promtail_s3_key  = "lambda-promtail/${local.lambda_promtail_version}/lambda-promtail-${local.lambda_promtail_version}.zip"
}

# --- Network ---
resource "aws_security_group" "lambda_promtail" {
  name                   = "${local.lambda_promtail_name}-sg"
  description            = "LookDDak ${var.environment} lambda-promtail"
  vpc_id                 = var.vpc_id
  revoke_rules_on_delete = true

  tags = merge(local.common_tags, {
    Name = "${local.lambda_promtail_name}-sg"
  })
}

resource "aws_vpc_security_group_egress_rule" "lambda_promtail_to_alloy" {
  security_group_id            = aws_security_group.lambda_promtail.id
  description                  = "Loki push to Alloy on the monitoring server"
  ip_protocol                  = "tcp"
  from_port                    = 3500
  to_port                      = 3500
  referenced_security_group_id = aws_security_group.this.id
}

data "aws_ec2_managed_prefix_list" "s3" {
  name = "com.amazonaws.${data.aws_region.current.region}.s3"
}

resource "aws_vpc_security_group_egress_rule" "lambda_promtail_to_s3" {
  security_group_id = aws_security_group.lambda_promtail.id
  description       = "Read ALB log files from S3"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  prefix_list_id    = data.aws_ec2_managed_prefix_list.s3.id
}

resource "aws_vpc_security_group_ingress_rule" "alloy_from_lambda_promtail" {
  security_group_id            = aws_security_group.this.id
  description                  = "Loki push from lambda-promtail"
  ip_protocol                  = "tcp"
  from_port                    = 3500
  to_port                      = 3500
  referenced_security_group_id = aws_security_group.lambda_promtail.id
}

# --- IAM ---
resource "aws_iam_role" "lambda_promtail" {
  name        = "${local.lambda_promtail_name}-role"
  description = "LookDDak ${var.environment} lambda-promtail execution role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = local.common_tags
}

# VPC ENI 생성 + 자체 로그 쓰기
resource "aws_iam_role_policy_attachment" "lambda_promtail_vpc" {
  role       = aws_iam_role.lambda_promtail.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy" "lambda_promtail_failed_queue" {
  name = "failed-queue-send"
  role = aws_iam_role.lambda_promtail.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "sqs:SendMessage"
      Resource = aws_sqs_queue.lambda_promtail_failed.arn
    }]
  })
}

# --- 자체 로그, 실패 큐 ---
resource "aws_cloudwatch_log_group" "lambda_promtail" {
  name              = "/aws/lambda/${local.lambda_promtail_name}"
  retention_in_days = 3

  tags = local.common_tags
}

resource "aws_sqs_queue" "lambda_promtail_failed" {
  name                      = "${local.lambda_promtail_name}-failed"
  message_retention_seconds = 1209600 # 14일
  sqs_managed_sse_enabled   = true

  tags = local.common_tags
}

# --- Function ---
resource "aws_lambda_function" "lambda_promtail" {
  function_name = local.lambda_promtail_name
  description   = "CloudWatch Logs subscription and S3 ALB logs to Loki (lambda-promtail ${local.lambda_promtail_version})"
  role          = aws_iam_role.lambda_promtail.arn

  s3_bucket     = aws_s3_bucket.lambda_artifacts.id
  s3_key        = local.lambda_promtail_s3_key
  runtime       = "provided.al2023"
  handler       = "bootstrap"
  architectures = ["x86_64"]

  # reserved_concurrent_executions는 두지 않는다: 계정 동시 실행 한도가 10이라
  # 예약하면 다른 함수가 쓸 수 있는 몫(최소 10)이 부족해져 AWS가 거부한다.
  memory_size = 128
  timeout     = 60

  vpc_config {
    subnet_ids         = var.lambda_subnet_ids
    security_group_ids = [aws_security_group.lambda_promtail.id]
  }

  # lambda-promtail 자체 로그(/aws/lambda/...) 설정. 전달하는 로그와는 무관하다.
  # - system_log_level WARN: 호출마다 찍히는 START·END·REPORT 줄을 남기지 않는다.
  # - application_log_level INFO: JSON 형식이면 AWS가 INFO로 채우는 기본값을 그대로 적어
  #   plan에 매번 변경이 보이지 않게 한다. 함수 로그를 실제로 줄이는 건 LOG_LEVEL이다.
  logging_config {
    log_format            = "JSON"
    log_group             = aws_cloudwatch_log_group.lambda_promtail.name
    application_log_level = "INFO"
    system_log_level      = "WARN"
  }

  environment {
    variables = {
      WRITE_ADDRESS            = "http://${aws_instance.this.private_ip}:3500/loki/api/v1/push"
      EXTRA_LABELS             = "env,${var.environment}"
      OMIT_EXTRA_LABELS_PREFIX = "true"
      KEEP_STREAM              = "false"
      PRINT_LOG_LINE           = "false"
      LOG_LEVEL                = "warn"
    }
  }

  tags = local.common_tags

  depends_on = [
    aws_cloudwatch_log_group.lambda_promtail,
    aws_iam_role_policy_attachment.lambda_promtail_vpc,
  ]
}

resource "aws_lambda_function_event_invoke_config" "lambda_promtail" {
  function_name                = aws_lambda_function.lambda_promtail.function_name
  maximum_retry_attempts       = 2
  maximum_event_age_in_seconds = 21600

  destination_config {
    on_failure {
      destination = aws_sqs_queue.lambda_promtail_failed.arn
    }
  }

  depends_on = [aws_iam_role_policy.lambda_promtail_failed_queue]
}

# --- 알람: 이름이 lookddak-로 시작하면 기존 EventBridge 규칙이 Discord로 보낸다 ---
resource "aws_cloudwatch_metric_alarm" "lambda_promtail_failed" {
  alarm_name          = "lookddak-${var.environment}-v2-lambda-promtail-failed"
  alarm_description   = "lambda-promtail이 재시도 후에도 Loki 전송에 실패해 실패 큐에 이벤트가 쌓임. Alloy·Loki 상태 확인 후 재처리"
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 1
  datapoints_to_alarm = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = aws_sqs_queue.lambda_promtail_failed.name
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "lambda_promtail_errors" {
  alarm_name          = "lookddak-${var.environment}-v2-lambda-promtail-errors"
  alarm_description   = "lambda-promtail 호출 오류. Alloy(:3500) 응답·보안 그룹 확인"
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  datapoints_to_alarm = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.lambda_promtail.function_name
  }

  tags = local.common_tags
}
