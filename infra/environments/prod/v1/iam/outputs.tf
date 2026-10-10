output "ec2_instance_profile_name" {
  description = "Name of the V1 EC2 instance profile"
  value       = aws_iam_instance_profile.ec2.name
}

output "eventbridge_role_arns" {
  description = "EventBridge → SQS 전송용 IAM Role ARN (규칙 키별)"
  value = {
    alarm_state_change = aws_iam_role.eventbridge_alarm_state_change.arn
    aws_health         = aws_iam_role.eventbridge_aws_health.arn
    docker_events      = aws_iam_role.eventbridge_docker_events.arn
    ec2_state_change   = aws_iam_role.eventbridge_ec2_state_change.arn
    rds_events         = aws_iam_role.eventbridge_rds_events.arn
  }
}

output "discord_alert_role_arn" {
  description = "Discord 알림 Lambda 실행 Role ARN"
  value       = aws_iam_role.discord_alert.arn
}
