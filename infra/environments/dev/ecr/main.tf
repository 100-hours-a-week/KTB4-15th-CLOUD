# ---------------------------------------------------------------
# dev 애플리케이션 이미지 저장소
# - prod 저장소(shared/core/ecr.tf)와 분리한다.
#   1. 태그 덮어쓰기 금지(IMMUTABLE)라 같은 커밋 SHA를 dev/prod가 함께 쓸 수 없다.
#   2. dev 빌드가 prod 롤백용 이미지를 수명 주기 정책으로 밀어내지 않게 한다.
# - V1 dev(EC2)와 V2 dev(ECS)가 함께 사용한다.
# ---------------------------------------------------------------
locals {
  services = toset(["nextjs", "spring", "fastapi", "crawler"])

  # 1. 태그 없는 이미지는 push 후 1일이 지나면 삭제
  # 2. 태그 있는 이미지는 최신 10개만 유지 (prod는 35개)
  lifecycle_policy = jsonencode({
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

resource "aws_ecr_repository" "this" {
  for_each = local.services

  name                 = "lookddak-dev-${each.key}"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Environment = "dev"
    Service     = each.key
  }
}

resource "aws_ecr_lifecycle_policy" "this" {
  for_each = local.services

  repository = aws_ecr_repository.this[each.key].name
  policy     = local.lifecycle_policy
}
