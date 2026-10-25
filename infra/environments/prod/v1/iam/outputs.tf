output "ec2_instance_profile_name" {
  description = "Name of the V1 EC2 instance profile"
  value       = aws_iam_instance_profile.ec2.name
}

output "eventbridge_role_arns" {
  description = "EventBridge → SQS 전송용 IAM Role ARN (규칙 키별)"
  value       = { for k, r in aws_iam_role.eventbridge : k => r.arn }
}

output "discord_alert_role_arn" {
  description = "Discord 알림 Lambda 실행 Role ARN"
  value       = aws_iam_role.discord_alert.arn
}

output "deploy_role_names" {
  description = "Names of the V1 application deployment roles"
  value = {
    fe = aws_iam_role.fe_deploy.name
    be = aws_iam_role.be_deploy.name
    ai = aws_iam_role.ai_deploy.name
  }
}

output "crawler_deploy_role_name" {
  description = "Name of the crawler prod CD deployment role (V2 task definition registration only)"
  value       = aws_iam_role.crawler_deploy.name
}
