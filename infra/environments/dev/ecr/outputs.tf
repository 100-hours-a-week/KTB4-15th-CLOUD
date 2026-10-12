# dev 애플리케이션 ECR 저장소 ARN ({ nextjs, spring, fastapi, crawler })
output "ecr_repository_arns" {
  description = "dev ECR 저장소 ARN (서비스 이름 => ARN)"
  value       = { for k, r in aws_ecr_repository.this : k => r.arn }
}
