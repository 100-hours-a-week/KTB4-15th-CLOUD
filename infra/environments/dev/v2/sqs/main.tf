locals {
  main_queues = {
    be-fitting-request = {
      visibility_timeout_seconds  = 120
      age_alarm_threshold_seconds = 180
    }
    ai-fitting-response = {
      visibility_timeout_seconds  = 300
      age_alarm_threshold_seconds = 600
    }
    be-fitting-response = {
      visibility_timeout_seconds  = 60
      age_alarm_threshold_seconds = 120
    }
  }

  common_tags = {
    Component   = "sqs"
    Environment = "dev"
    Service     = "fitting"
    Version     = "v2"
  }
}

resource "aws_sqs_queue" "dlq" {
  for_each = local.main_queues

  name                       = "lookddak-dev-v2-${each.key}-dlq"
  message_retention_seconds  = 1209600 # 14 days
  visibility_timeout_seconds = 30
  max_message_size           = 262144 # 256 KiB
  sqs_managed_sse_enabled    = true

  tags = merge(local.common_tags, {
    Name      = "lookddak-dev-v2-${each.key}-dlq"
    QueueRole = "dead-letter"
  })
}

resource "aws_sqs_queue" "main" {
  for_each = local.main_queues

  name                       = "lookddak-dev-v2-${each.key}"
  delay_seconds              = 0
  visibility_timeout_seconds = each.value.visibility_timeout_seconds
  message_retention_seconds  = 345600 # 4 days
  max_message_size           = 262144 # 256 KiB
  receive_wait_time_seconds  = 20
  sqs_managed_sse_enabled    = true

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq[each.key].arn
    maxReceiveCount     = 3
  })

  tags = merge(local.common_tags, {
    Name      = "lookddak-dev-v2-${each.key}"
    QueueRole = "main"
  })
}

resource "aws_sqs_queue_redrive_allow_policy" "dlq" {
  for_each = local.main_queues

  queue_url = aws_sqs_queue.dlq[each.key].id
  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue"
    sourceQueueArns   = [aws_sqs_queue.main[each.key].arn]
  })
}

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
