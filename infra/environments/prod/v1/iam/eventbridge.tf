# ---------------------------------------------------------------
# EventBridge 규칙 → SQS(alert-queue) 전송용 IAM Role/Policy
# - 콘솔이 규칙마다 자동 생성한 Role·Policy를 import한 것으로, Role과 Policy 이름이 같다.
# - 규칙 키는 prod/v1/monitoring의 EventBridge 규칙 키와 같다.
# ---------------------------------------------------------------
locals {
  eventbridge_sqs = {
    alarm_state_change = { name = "Amazon_EventBridge_Invoke_Sqs_1504746143", rule = "lookddak-alarm-state-change" }
    aws_health         = { name = "Amazon_EventBridge_Invoke_Sqs_1568336830", rule = "lookddak-aws-health" }
    docker_events      = { name = "Amazon_EventBridge_Invoke_Sqs_2071571937", rule = "lookddak-docker-events" }
    ec2_state_change   = { name = "Amazon_EventBridge_Invoke_Sqs_1541928649", rule = "lookddak-ec2-state-change" }
    rds_events         = { name = "Amazon_EventBridge_Invoke_Sqs_533425366", rule = "lookddak-rds-events" }
  }

  alert_queue_arn = "arn:aws:sqs:${local.region}:${local.account_id}:lookddak-alert-queue"
}

resource "aws_iam_role" "eventbridge" {
  for_each = local.eventbridge_sqs

  name = each.value.name
  path = "/service-role/"
  assume_role_policy = jsonencode({
    Statement = [{
      Action = "sts:AssumeRole"
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = local.account_id
          "aws:SourceArn"     = "arn:aws:events:${local.region}:${local.account_id}:rule/${each.value.rule}"
        }
      }
      Effect = "Allow"
      Principal = {
        Service = "events.amazonaws.com"
      }
      Sid = "TrustEventBridgeService"
    }]
    Version = "2012-10-17"
  })
  tags = {}
}

resource "aws_iam_policy" "eventbridge" {
  for_each = local.eventbridge_sqs

  name = each.value.name
  path = "/service-role/"
  policy = jsonencode({
    Statement = [{
      Action   = ["sqs:SendMessage"]
      Effect   = "Allow"
      Resource = [local.alert_queue_arn]
    }]
    Version = "2012-10-17"
  })
  tags = {}
}

resource "aws_iam_role_policy_attachment" "eventbridge" {
  for_each = local.eventbridge_sqs

  role       = aws_iam_role.eventbridge[each.key].name
  policy_arn = aws_iam_policy.eventbridge[each.key].arn
}
