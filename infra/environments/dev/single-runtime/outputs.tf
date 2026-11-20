output "ecr_repository_urls" {
  description = "Single Dev service ECR repository URLs"
  value       = { for name, repository in aws_ecr_repository.service : name => repository.repository_url }
}

output "images_bucket_name" {
  description = "Existing durable image bucket reused by Single Dev"
  value       = data.aws_s3_bucket.images.id
}

output "backup_bucket_name" {
  description = "Single Dev database backup bucket"
  value       = aws_s3_bucket.database_backup.id
}

output "fitting_queue_urls" {
  description = "Existing Dev V2 Fitting Queue URLs reused by Single Dev"
  value       = { for name, queue in data.aws_sqs_queue.fitting_main : name => queue.url }
}

output "fitting_dlq_urls" {
  description = "Existing Dev V2 Fitting DLQ URLs retained without modification"
  value       = { for name, queue in data.aws_sqs_queue.fitting_dlq : name => queue.url }
}

output "log_group_name" {
  description = "Single Dev Docker Compose log group"
  value       = aws_cloudwatch_log_group.runtime.name
}

output "runtime_parameter_arn" {
  description = "SSM ARN prefix readable by the Single Dev EC2 role"
  value       = "arn:${data.aws_partition.current.partition}:ssm:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:parameter/lookddak/dev/single/*"
}

output "modal_body_image_worker_user_name" {
  description = "Upload-only IAM user for the Modal body image worker"
  value       = aws_iam_user.modal_body_image_worker.name
}
