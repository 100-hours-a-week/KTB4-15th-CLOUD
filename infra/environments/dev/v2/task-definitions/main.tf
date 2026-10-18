# ---------------------------------------------------------------
# V2 dev Task Definition 템플릿
# - Terraform은 템플릿만 S3(dev/v2/<service>.json)에 올린다.
# - revision 등록은 앱 레포 CI가 한다 (템플릿 + 이미지 digest).
# - 이 값을 바꾸고 apply하면 다음 배포부터 반영된다.
#   실행 중인 Task를 바로 바꾸려면 현재 태그로 재배포한다.
# - crawler는 아직 dev/v2/task-definitions/crawler.json 사용 (마지막에 옮김)
# ---------------------------------------------------------------
locals {
  ssm = "/lookddak/dev"

  # V2 Spring이 쓰는 MySQL JDBC URL (var.spring_mysql_target). 둘 다 SSM에서 읽는다.
  # - v1: V1 dev 구 DB(lookddak-dev-mysql) → /lookddak/dev/rds/app/jdbc-url
  # - v2: V2 Dev MySQL                    → /lookddak/dev/v2/mysql/jdbc-url
  spring_db_url_parameter = {
    v1 = "${local.ssm}/rds/app/jdbc-url"
    v2 = "${local.ssm}/v2/mysql/jdbc-url"
  }

  services = {
    nextjs = {
      cpu    = 512
      memory = 1024
      environment = {
        API_BASE_URL = "http://spring:8080"
        NODE_ENV     = "production"
        NODE_OPTIONS = "--max-old-space-size=384"
        TZ           = "Asia/Seoul"
      }
      secrets       = {}
      port_mappings = [{ name = "nextjs-http", container_port = 3000 }]
      health_check  = null
    }

    spring = {
      cpu    = 1024
      memory = 2048
      environment = {
        SPRING_PROFILES_ACTIVE        = "prod"
        AWS_REGION                    = "ap-northeast-2"
        AWS_S3_BUCKET                 = var.images_bucket_name
        AI_SERVER_URL                 = "http://fastapi:8000"
        CORS_ALLOWED_ORIGINS          = "https://dev.lookddak.com,https://v2-dev.lookddak.com"
        SENTRY_ENVIRONMENT            = "dev"
        BE_FITTING_REQUEST_QUEUE_URL  = var.queue_urls["be-fitting-request"]
        BE_FITTING_RESPONSE_QUEUE_URL = var.queue_urls["be-fitting-response"]
        JAVA_TOOL_OPTIONS             = "-XX:MaxRAMPercentage=75.0 -XX:InitialRAMPercentage=25.0 -XX:MaxMetaspaceSize=192m -XX:+UseContainerSupport -Dnetworkaddress.cache.ttl=10"
        TZ                            = "Asia/Seoul"
      }
      secrets = {
        DB_URL              = local.spring_db_url_parameter[var.spring_mysql_target]
        DB_USERNAME         = "${local.ssm}/rds/app/username"
        DB_PASSWORD         = "${local.ssm}/rds/app/password"
        JWT_SECRET          = "${local.ssm}/spring/jwt-secret"
        AI_INTERNAL_API_KEY = "${local.ssm}/internal/ai-api-key"
        SENTRY_DSN          = "${local.ssm}/spring/sentry_dsn"
      }
      port_mappings = [{ name = "spring-http", container_port = 8080 }]
      health_check  = null
    }

    fastapi = {
      cpu    = 1024
      memory = 2048
      environment = {
        AWS_REGION                        = "ap-northeast-2"
        S3_BUCKET                         = var.images_bucket_name
        BODY_IMAGE_VALIDATION_MODE        = "remote"
        BE_FITTING_REQUEST_QUEUE_URL      = var.queue_urls["be-fitting-request"]
        AI_FITTING_RESPONSE_QUEUE_URL     = var.queue_urls["ai-fitting-response"]
        BE_FITTING_RESPONSE_QUEUE_URL     = var.queue_urls["be-fitting-response"]
        WEB_CONCURRENCY                   = "1"
        MALLOC_ARENA_MAX                  = "2"
        UVICORN_TIMEOUT_GRACEFUL_SHUTDOWN = "30"
        TZ                                = "Asia/Seoul"
      }
      secrets = {
        DATABASE_URL                   = "${local.ssm}/v2/postgresql/app/database-url"
        CHECKPOINT_DSN                 = "${local.ssm}/v2/postgresql/app/checkpoint-dsn"
        INTERNAL_API_KEY               = "${local.ssm}/internal/ai-api-key"
        RUNWARE_VTON_API_KEY           = "${local.ssm}/fastapi/runware-vton-api-key"
        RUNWARE_LLM_API_KEY            = "${local.ssm}/fastapi/runware-llm-api-key"
        OPENAI_API_KEY                 = "${local.ssm}/fastapi/openAI-api-key"
        BODY_IMAGE_REMOTE_URL          = "${local.ssm}/fastapi/body-image-validation/url"
        BODY_IMAGE_REMOTE_PROXY_KEY    = "${local.ssm}/fastapi/body-image-validation/proxy-key"
        BODY_IMAGE_REMOTE_PROXY_SECRET = "${local.ssm}/fastapi/body-image-validation/proxy-secret"
        BODY_IMAGE_REMOTE_API_KEY      = "${local.ssm}/fastapi/body-image-validation/api-key"
      }
      port_mappings = [{ name = "fastapi-http", container_port = 8000 }]

      # V1 compose와 같은 방식: /health 라우트가 없어 8000 포트 TCP 연결만 확인한다.
      # ALB가 없어 이 헬스 체크가 배포 중 비정상 Task 판단 기준이 된다.
      health_check = {
        command      = ["CMD", "python", "-c", "import socket; socket.create_connection(('localhost', 8000), 3).close()"]
        interval     = 30
        timeout      = 5
        retries      = 3
        start_period = 180
      }
    }
  }
}

module "template" {
  source   = "../../../../modules/ecs-taskdef-template"
  for_each = local.services

  bucket_name = var.bucket_name
  s3_key      = "dev/v2/${each.key}.json"

  family             = "lookddak-dev-v2-${each.key}"
  cpu                = each.value.cpu
  memory             = each.value.memory
  task_role_arn      = var.task_role_arns[each.key]
  execution_role_arn = var.task_execution_role_arn

  container_name       = each.key
  image_repository_url = var.ecr_repository_urls[each.key]
  environment          = each.value.environment
  secrets              = each.value.secrets
  port_mappings        = each.value.port_mappings
  log_group_name       = var.log_group_names[each.key]
  health_check         = each.value.health_check

  tags = {
    Environment = "dev"
    Service     = each.key
    Version     = "v2"
  }
}
