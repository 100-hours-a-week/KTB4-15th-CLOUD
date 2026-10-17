# dev 애플리케이션 ECR 저장소 ARN ({ nextjs, spring, fastapi, crawler })
output "ecr_repository_arns" {
  description = "dev ECR 저장소 ARN (서비스 이름 => ARN)"
  value       = { for k, r in aws_ecr_repository.this : k => r.arn }
}

# dev 애플리케이션 ECR 저장소 URL ({ nextjs, spring, fastapi, crawler })
output "repository_urls" {
  description = "dev ECR 저장소 URL (서비스 이름 => URL)"
  value       = { for k, r in aws_ecr_repository.this : k => r.repository_url }
}
