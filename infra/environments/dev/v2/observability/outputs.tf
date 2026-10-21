output "instance_id" {
  description = "Monitoring server instance ID"
  value       = aws_instance.this.id
}

output "private_ip" {
  description = "Fixed private IP of the monitoring server"
  value       = aws_instance.this.private_ip
}

output "security_group_id" {
  description = "Monitoring server security group ID"
  value       = aws_security_group.this.id
}

output "instance_role_name" {
  description = "Monitoring server IAM role name"
  value       = aws_iam_role.instance.name
}

output "ecs_task_stopped_log_group_name" {
  description = "CloudWatch log group receiving dev V2 ECS task stopped events"
  value       = aws_cloudwatch_log_group.ecs_task_stopped.name
}

output "lambda_artifacts_bucket_name" {
  description = "S3 bucket for dev Lambda deployment packages"
  value       = aws_s3_bucket.lambda_artifacts.bucket
}

output "lambda_promtail_function_name" {
  description = "lambda-promtail function name"
  value       = aws_lambda_function.lambda_promtail.function_name
}
