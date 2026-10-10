# ---------------------------------------------------------------
# EventBridge 규칙: 감시할 이벤트를 골라 alert-queue(SQS)로 보낸다
# ---------------------------------------------------------------
locals {
  alert_rules = {
    alarm_state_change = {
      name      = "lookddak-alarm-state-change"
      target_id = "Id5ebf6260-9768-48e8-8997-990ccc4cb19d"
      pattern = {
        source        = ["aws.cloudwatch"]
        "detail-type" = ["CloudWatch Alarm State Change"]
        detail = {
          alarmName = [{ prefix = "lookddak-" }]
          state     = { value = ["ALARM", "OK"] }
        }
      }
    }
    aws_health = {
      name      = "lookddak-aws-health"
      target_id = "Ida562fc30-dec6-4c51-b2a3-406e63ca6c14"
      pattern = {
        source        = ["aws.health"]
        "detail-type" = ["AWS Health Event"]
        detail = {
          service           = ["EC2", "EBS", "ECR", "LAMBDA", "SQS"]
          eventTypeCategory = ["issue", "scheduledChange"]
        }
      }
    }
    docker_events = {
      name      = "lookddak-docker-events"
      target_id = "Idbcc7eb30-dd93-4cad-8eb9-d8c9f63d97c9"
      pattern = {
        source        = ["custom.docker"]
        "detail-type" = ["Container State Change"]
      }
    }
    ec2_state_change = {
      name      = "lookddak-ec2-state-change"
      target_id = "Ida2188ef3-263c-42f9-b7de-ca0a4cb8a6ca"
      pattern = {
        source        = ["aws.ec2"]
        "detail-type" = ["EC2 Instance State-change Notification"]
        detail = {
          state = ["stopping", "stopped", "shutting-down", "terminated"]
        }
      }
    }
    rds_events = {
      name      = "lookddak-rds-events"
      target_id = "Id052879a0-9e55-4e57-8b77-51d6420fef3e"
      pattern = {
        source        = ["aws.rds"]
        "detail-type" = ["RDS DB Instance Event"]
        detail = {
          EventCategories = ["failure", "failover", "availability", "low storage", "maintenance", "recovery"]
        }
      }
    }
  }
}

resource "aws_cloudwatch_event_rule" "alert" {
  for_each = local.alert_rules

  name          = each.value.name
  event_pattern = jsonencode(each.value.pattern)
  state         = "ENABLED"
}

resource "aws_cloudwatch_event_target" "alert" {
  for_each = local.alert_rules

  rule      = aws_cloudwatch_event_rule.alert[each.key].name
  target_id = each.value.target_id
  arn       = aws_sqs_queue.alert.arn
  role_arn  = var.eventbridge_role_arns[each.key]
}
