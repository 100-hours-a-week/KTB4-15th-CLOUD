locals {
  main_queues = {
    be-fitting-request = {
      visibility_timeout_seconds = 120
    }
    ai-fitting-response = {
      visibility_timeout_seconds = 300
    }
    be-fitting-response = {
      visibility_timeout_seconds = 60
    }
  }

  common_tags = {
    Component   = "sqs"
    Environment = "dev"
    Service     = "fitting"
    Version     = "v3"
  }
}

# 처리에 세 번 실패한 메시지를 보관하는 워크로드별 DLQ이다.
resource "aws_sqs_queue" "dlq" {
  for_each = local.main_queues

  name                       = "lookddak-dev-v3-${each.key}-dlq"
  message_retention_seconds  = 1209600 # 14일
  visibility_timeout_seconds = 30
  max_message_size           = 262144 # 256KiB
  sqs_managed_sse_enabled    = true

  tags = merge(local.common_tags, {
    Name      = "lookddak-dev-v3-${each.key}-dlq"
    QueueRole = "dead-letter"
  })
}

# V2 Consumer와 메시지를 경쟁하지 않는 V3 피팅 전용 Main Queue이다.
resource "aws_sqs_queue" "main" {
  for_each = local.main_queues

  name                       = "lookddak-dev-v3-${each.key}"
  delay_seconds              = 0
  visibility_timeout_seconds = each.value.visibility_timeout_seconds
  message_retention_seconds  = 345600 # 4일
  max_message_size           = 262144 # 256KiB
  receive_wait_time_seconds  = 20
  sqs_managed_sse_enabled    = true

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq[each.key].arn
    maxReceiveCount     = 3
  })

  tags = merge(local.common_tags, {
    Name      = "lookddak-dev-v3-${each.key}"
    QueueRole = "main"
  })
}

# 각 DLQ는 같은 역할의 Main Queue에서 이동한 메시지만 받는다.
resource "aws_sqs_queue_redrive_allow_policy" "dlq" {
  for_each = local.main_queues

  queue_url = aws_sqs_queue.dlq[each.key].id
  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue"
    sourceQueueArns   = [aws_sqs_queue.main[each.key].arn]
  })
}

# 암호화되지 않은 HTTP 요청으로 Main Queue에 접근하는 것을 거부한다.
resource "aws_sqs_queue_policy" "main_tls" {
  for_each = local.main_queues

  queue_url = aws_sqs_queue.main[each.key].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "sqs:*"
      Resource  = aws_sqs_queue.main[each.key].arn
      Condition = {
        Bool = {
          "aws:SecureTransport" = "false"
        }
      }
    }]
  })
}

# 암호화되지 않은 HTTP 요청으로 DLQ에 접근하는 것을 거부한다.
resource "aws_sqs_queue_policy" "dlq_tls" {
  for_each = local.main_queues

  queue_url = aws_sqs_queue.dlq[each.key].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "sqs:*"
      Resource  = aws_sqs_queue.dlq[each.key].arn
      Condition = {
        Bool = {
          "aws:SecureTransport" = "false"
        }
      }
    }]
  })
}
