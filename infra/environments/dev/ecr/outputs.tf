# shared_core.ecr_repository_arns와 같은 형태 ({ nextjs, spring, fastapi })
output "ecr_repository_arns" {
  description = "dev ECR 저장소 ARN (서비스 이름 => ARN)"
  value       = { for k, r in aws_ecr_repository.this : k => r.arn }
}
