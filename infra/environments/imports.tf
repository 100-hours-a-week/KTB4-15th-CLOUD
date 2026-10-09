# V1 리소스 import 블록
# apply로 state에 편입된 뒤에는 이 파일을 삭제한다.

# ---------------------------------------------------------------
# ECR Repository (id: 저장소 이름)
# ---------------------------------------------------------------
import {
  to = module.shared_core.aws_ecr_repository.nextjs
  id = "lookddak-nextjs"
}

import {
  to = module.shared_core.aws_ecr_repository.spring
  id = "lookddak-spring"
}

import {
  to = module.shared_core.aws_ecr_repository.fastapi
  id = "lookddak-fastapi"
}

import {
  to = module.shared_core.aws_ecr_repository.crawler
  id = "lookddak-crawler"
}

# ---------------------------------------------------------------
# ECR Lifecycle Policy (id: 저장소 이름)
# ---------------------------------------------------------------
import {
  to = module.shared_core.aws_ecr_lifecycle_policy.nextjs
  id = "lookddak-nextjs"
}

import {
  to = module.shared_core.aws_ecr_lifecycle_policy.spring
  id = "lookddak-spring"
}

import {
  to = module.shared_core.aws_ecr_lifecycle_policy.fastapi
  id = "lookddak-fastapi"
}

import {
  to = module.shared_core.aws_ecr_lifecycle_policy.crawler
  id = "lookddak-crawler"
}
