# ---------------------------------------------------------------
# 알림 큐: EventBridge → alert-queue → Lambda
# Lambda가 5번 실패한 메시지는 DLQ로 이동한다.
# 큐 정책은 계정 기본 정책뿐이라 따로 관리하지 않는다.
# ---------------------------------------------------------------
resource "aws_sqs_queue" "alert" {
  name                       = "lookddak-alert-queue"
  visibility_timeout_seconds = 90
  message_retention_seconds  = 345600 # 4일
  max_message_size           = 1048576
  sqs_managed_sse_enabled    = true

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.alert_dlq.arn
    maxReceiveCount     = 5
  })
}

resource "aws_sqs_queue" "alert_dlq" {
  name                       = "lookddak-alert-dlq"
  visibility_timeout_seconds = 30
  message_retention_seconds  = 604800 # 7일
  max_message_size           = 1048576
  sqs_managed_sse_enabled    = true
}
