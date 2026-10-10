variable "eventbridge_role_arns" {
  description = "EventBridge 규칙이 SQS로 이벤트를 보낼 때 사용하는 IAM Role ARN (규칙 키별)"
  type = object({
    alarm_state_change = string
    aws_health         = string
    docker_events      = string
    ec2_state_change   = string
    rds_events         = string
  })
}

variable "discord_alert_role_arn" {
  description = "Discord 알림 Lambda 실행 Role ARN"
  type        = string
}
