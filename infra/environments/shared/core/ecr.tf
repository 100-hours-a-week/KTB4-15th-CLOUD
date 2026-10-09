# ---------------------------------------------------------------
# ECR 수명 주기 정책 (콘솔에서 설정한 기존 정책을 그대로 옮김)
#   1. 태그 없는 이미지는 push 후 1일이 지나면 삭제
#   2. 태그 있는 이미지는 최신 N개만 유지
# ---------------------------------------------------------------
locals {
  ecr_lifecycle_policy_keep_35 = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images older than 1 day"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 1
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep the most recent 35 tagged images"
        selection = {
          tagStatus      = "tagged"
          tagPatternList = ["*"]
          countType      = "imageCountMoreThan"
          countNumber    = 35
        }
        action = { type = "expire" }
      },
    ]
  })

  ecr_lifecycle_policy_keep_10 = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images older than 1 day"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 1
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep the most recent 10 tagged images"
        selection = {
          tagStatus      = "tagged"
          tagPatternList = ["*"]
          countType      = "imageCountMoreThan"
          countNumber    = 10
        }
        action = { type = "expire" }
      },
    ]
  })
}

# ---------------------------------------------------------------
# Next.js
# ---------------------------------------------------------------
resource "aws_ecr_repository" "nextjs" {
  name                 = "lookddak-nextjs"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Environment = "prod"
    Service     = "nextjs"
  }
}

resource "aws_ecr_lifecycle_policy" "nextjs" {
  repository = aws_ecr_repository.nextjs.name
  policy     = local.ecr_lifecycle_policy_keep_35
}

# ---------------------------------------------------------------
# Spring
# ---------------------------------------------------------------
resource "aws_ecr_repository" "spring" {
  name                 = "lookddak-spring"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Environment = "prod"
    Service     = "spring"
  }
}

resource "aws_ecr_lifecycle_policy" "spring" {
  repository = aws_ecr_repository.spring.name
  policy     = local.ecr_lifecycle_policy_keep_35
}

# ---------------------------------------------------------------
# FastAPI
# ---------------------------------------------------------------
resource "aws_ecr_repository" "fastapi" {
  name                 = "lookddak-fastapi"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Environment = "prod"
    Service     = "fastapi"
  }
}

resource "aws_ecr_lifecycle_policy" "fastapi" {
  repository = aws_ecr_repository.fastapi.name
  policy     = local.ecr_lifecycle_policy_keep_35
}

# ---------------------------------------------------------------
# Crawler (미사용: 이미지 0개, import 후 정리 PR에서 삭제 예정)
# ---------------------------------------------------------------
resource "aws_ecr_repository" "crawler" {
  name                 = "lookddak-crawler"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Environment = "prod"
    Service     = "crawler"
  }
}

resource "aws_ecr_lifecycle_policy" "crawler" {
  repository = aws_ecr_repository.crawler.name
  policy     = local.ecr_lifecycle_policy_keep_10
}
