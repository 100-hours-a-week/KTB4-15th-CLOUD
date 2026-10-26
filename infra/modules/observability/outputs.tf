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
  description = "CloudWatch log group receiving V2 ECS task stopped events"
  value       = aws_cloudwatch_log_group.ecs_task_stopped.name
}

output "lambda_artifacts_bucket_name" {
  description = "S3 bucket for Lambda deployment packages"
  value       = aws_s3_bucket.lambda_artifacts.bucket
}

output "lambda_promtail_function_name" {
  description = "lambda-promtail function name"
  value       = aws_lambda_function.lambda_promtail.function_name
}

output "alb_logs_bucket_name" {
  description = "S3 bucket for V2 ALB access logs (bucket policy applied)"
  value       = aws_s3_bucket_policy.alb_logs.bucket
}

output "grafana_target_group_arn" {
  description = "Grafana target group ARN"
  value       = aws_lb_target_group.grafana.arn
}

output "grafana_url" {
  description = "Grafana public URL"
  value       = "https://${aws_route53_record.grafana.fqdn}"
}

output "grafana_user_pool_id" {
  description = "Cognito user pool ID for Grafana users"
  value       = aws_cognito_user_pool.grafana.id
}

output "fluent_bit_config_arn" {
  description = "FireLens Loki 출력 설정 파일 S3 객체 ARN"
  value       = "arn:${data.aws_partition.current.partition}:s3:::${aws_s3_object.fluent_bit_loki.bucket}/${aws_s3_object.fluent_bit_loki.key}"
}

output "loki_bucket_name" {
  description = "Loki S3 bucket (server .env LOKI_S3_BUCKET)"
  value       = aws_s3_bucket.loki.id
}

output "tempo_bucket_name" {
  description = "Tempo S3 bucket (server .env TEMPO_S3_BUCKET)"
  value       = aws_s3_bucket.tempo.id
}

output "fluent_bit_parsers_arn" {
  description = "FireLens 여러 줄 합치기 규칙 파일 S3 객체 ARN"
  value       = "arn:${data.aws_partition.current.partition}:s3:::${aws_s3_object.fluent_bit_parsers.bucket}/${aws_s3_object.fluent_bit_parsers.key}"
}

output "grafana_cloudfront_distribution_id" {
  description = "Grafana CloudFront distribution ID (grafana_cloudfront_enabled일 때)"
  value       = try(aws_cloudfront_distribution.grafana[0].id, null)
}
