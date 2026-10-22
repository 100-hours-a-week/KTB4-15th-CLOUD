output "ecr_repository_arns" {
  description = "ARNs of the shared application ECR repositories"
  value = {
    nextjs  = aws_ecr_repository.nextjs.arn
    spring  = aws_ecr_repository.spring.arn
    fastapi = aws_ecr_repository.fastapi.arn
    crawler = aws_ecr_repository.crawler.arn
  }
}

output "ecr_repository_urls" {
  description = "URLs of the shared application ECR repositories"
  value = {
    nextjs  = aws_ecr_repository.nextjs.repository_url
    spring  = aws_ecr_repository.spring.repository_url
    fastapi = aws_ecr_repository.fastapi.repository_url
    crawler = aws_ecr_repository.crawler.repository_url
  }
}

output "route53_zone_id" {
  description = "lookddak.com Hosted Zone ID"
  value       = aws_route53_zone.main.zone_id
}
