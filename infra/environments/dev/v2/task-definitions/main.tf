# ---------------------------------------------------------------
# V2 dev Task Definition 템플릿
# - Terraform은 템플릿만 S3(dev/v2/<service>.json)에 올린다.
# - revision 등록은 앱 레포 CI가 한다 (템플릿 + 이미지 digest).
# - 이 값을 바꾸고 apply하면 다음 배포부터 반영된다.
#   실행 중인 Task를 바로 바꾸려면 현재 태그로 재배포한다.
# - crawler(가격 갱신)는 서비스가 아니라 EventBridge Scheduler가 RunTask로 실행한다.
#   Scheduler가 family ARN으로 최신 ACTIVE revision을 실행하므로 CI는 revision 등록만 한다.
# ---------------------------------------------------------------
locals {
  ssm = "/lookddak/dev"


  services = {
    nextjs = {
      cpu    = 512
      memory = 1024
      environment = {
        # FE serverApi가 new URL("members/me", API_BASE_URL)로 경로를 붙이므로 /api/v1/ 과 끝 슬래시가 필요하다.
        API_BASE_URL = "http://spring:8080/api/v1/"
        NODE_ENV     = "production"
        NODE_OPTIONS = "--max-old-space-size=384"
        TZ           = "Asia/Seoul"
      }
      secrets       = {}
      port_mappings = [{ name = "nextjs-http", container_port = 3000 }]
      command       = null
      health_check  = null
    }

    spring = {
      cpu    = 1024
      memory = 2048
      environment = {
        SPRING_PROFILES_ACTIVE          = "prod"
        AWS_REGION                      = "ap-northeast-2"
        AWS_S3_BUCKET                   = var.images_bucket_name
        AI_SERVER_URL                   = "http://fastapi:8000"
        CORS_ALLOWED_ORIGINS            = "https://dev.lookddak.com,https://v2-dev.lookddak.com"
        SENTRY_ENVIRONMENT              = "dev"
        SSE_SERVER_PORT                 = "8081"
        BE_FITTING_REQUEST_QUEUE_URL    = var.queue_urls["be-fitting-request"]
        BE_FITTING_RESPONSE_QUEUE_URL   = var.queue_urls["be-fitting-response"]
        FITTING_OUTBOX_ENABLED          = "true"
        FITTING_RESULT_CONSUMER_ENABLED = "true"
        JAVA_TOOL_OPTIONS               = "-XX:MaxRAMPercentage=75.0 -XX:InitialRAMPercentage=25.0 -XX:MaxMetaspaceSize=192m -XX:+UseContainerSupport -Dnetworkaddress.cache.ttl=10"
        TZ                              = "Asia/Seoul"
      }
      secrets = {
        DB_URL              = "${local.ssm}/v2/mysql/jdbc-url"
        DB_USERNAME         = "${local.ssm}/rds/app/username"
        DB_PASSWORD         = "${local.ssm}/rds/app/password"
        JWT_SECRET          = "${local.ssm}/spring/jwt-secret"
        AI_INTERNAL_API_KEY = "${local.ssm}/internal/ai-api-key"
        INTERNAL_API_KEY    = "${local.ssm}/spring/internal-api-key"
        SENTRY_DSN          = "${local.ssm}/spring/sentry_dsn"
      }
      port_mappings = [
        { name = "spring-http", container_port = 8080 },
        { name = "spring-sse", container_port = 8081 },
      ]
      command      = null
      health_check = null
    }

    fastapi = {
      cpu    = 1024
      memory = 2048
      environment = {
        AWS_REGION                                 = "ap-northeast-2"
        S3_BUCKET                                  = var.images_bucket_name
        BODY_IMAGE_VALIDATION_MODE                 = "remote"
        BE_FITTING_REQUEST_QUEUE_URL               = var.queue_urls["be-fitting-request"]
        AI_FITTING_RESPONSE_QUEUE_URL              = var.queue_urls["ai-fitting-response"]
        BE_FITTING_RESPONSE_QUEUE_URL              = var.queue_urls["be-fitting-response"]
        VIRTUAL_FITTING_REQUEST_WORKER_ENABLED     = "true"
        VIRTUAL_FITTING_POSTPROCESS_WORKER_ENABLED = "true"
        VIRTUAL_FITTING_RESULT_PUBLISHER_ENABLED   = "true"
        VIRTUAL_FITTING_WATCHDOG_ENABLED           = "true"
        WEB_CONCURRENCY                            = "1"
        MALLOC_ARENA_MAX                           = "2"
        UVICORN_TIMEOUT_GRACEFUL_SHUTDOWN          = "30"
        TZ                                         = "Asia/Seoul"
      }
      secrets = {
        DATABASE_URL                        = "${local.ssm}/v2/postgresql/app/database-url"
        CHECKPOINT_DSN                      = "${local.ssm}/v2/postgresql/app/checkpoint-dsn"
        INTERNAL_API_KEY                    = "${local.ssm}/internal/ai-api-key"
        RUNWARE_VTON_API_KEY                = "${local.ssm}/fastapi/runware-vton-api-key"
        RUNWARE_LLM_API_KEY                 = "${local.ssm}/fastapi/runware-llm-api-key"
        OPENAI_API_KEY                      = "${local.ssm}/fastapi/openAI-api-key"
        WEBHOOK_TOKEN                       = "${local.ssm}/fastapi/webhook-token"
        VIRTUAL_FITTING_RUNWARE_WEBHOOK_URL = "${local.ssm}/fastapi/virtual-fitting-runware-webhook-url"
        BODY_IMAGE_REMOTE_URL               = "${local.ssm}/fastapi/body-image-validation/url"
        BODY_IMAGE_REMOTE_PROXY_KEY         = "${local.ssm}/fastapi/body-image-validation/proxy-key"
        BODY_IMAGE_REMOTE_PROXY_SECRET      = "${local.ssm}/fastapi/body-image-validation/proxy-secret"
        BODY_IMAGE_REMOTE_API_KEY           = "${local.ssm}/fastapi/body-image-validation/api-key"
      }
      port_mappings = [{ name = "fastapi-http", container_port = 8000 }]
      command       = null

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

    # 가격 갱신 크롤러 (KTB4-15th-Crawler/price-refresh-crawler)
    # - 29CM 가격 수집 → V2 PostgreSQL products.price 갱신 → 추천된 상품만 BE에 PATCH /api/v1/internal/products
    # - BE는 Service Connect(HTTP namespace) 밖이라 ALB 주소로 호출한다.
    # - BE 인증: X-Internal-Api-Key 헤더, 값은 Spring INTERNAL_API_KEY(/lookddak/dev/spring/internal-api-key)와 같다.
    # - 스펙은 기존 crawler.json 값 유지 (실측 후 조정)
    crawler = {
      cpu    = 1024
      memory = 2048
      environment = {
        PRICE_REFRESH_BACKEND_BASE_URL = "https://dev.lookddak.com"
        TZ                             = "Asia/Seoul"
      }
      secrets = {
        DATABASE_URL                            = "${local.ssm}/v2/postgresql/app/database-url"
        PRICE_REFRESH_BACKEND_AUTH_HEADERS_JSON = "${local.ssm}/internal/price-refresh-backend-auth-headers"
      }
      port_mappings = []
      command       = ["--apply"]
      health_check  = null
    }
  }
}

# ---------------------------------------------------------------
# 모니터링 사이드카: ecs_exporter (Task CPU·메모리·네트워크 → :9779/metrics)
# - 계속 떠 있는 서비스(nextjs, spring, fastapi)에만 붙인다. crawler(배치)는 제외.
# - essential = false: 죽어도 앱 Task는 계속 돈다.
# - Task 메타데이터 엔드포인트(169.254.170.2)를 읽으므로 IAM 권한이 필요 없다.
# - 템플릿은 다음 앱 배포 때 반영된다. 앱 CD가 앱 컨테이너를 이름으로 찾도록
#   바뀐 뒤에 적용해야 한다 (예전 CD는 컨테이너가 1개가 아니면 배포를 멈춘다).
# ---------------------------------------------------------------
locals {
  ecs_exporter_image    = "quay.io/prometheuscommunity/ecs-exporter:v0.4.0"
  ecs_exporter_services = ["nextjs", "spring", "fastapi"]

  # 서비스마다 사이드카 목록. 목록 모양이 달라 map 대신 object로 둔다.
  sidecars = {
    for service in keys(local.services) : service => (
      contains(local.ecs_exporter_services, service) ? [
        {
          name              = "ecs-exporter"
          image             = local.ecs_exporter_image
          essential         = false
          memory            = 64
          memoryReservation = 32
          portMappings = [{
            containerPort = 9779
            hostPort      = 9779
            protocol      = "tcp"
          }]
          logConfiguration = {
            logDriver = "awslogs"
            options = {
              "awslogs-group"         = var.log_group_names[service]
              "awslogs-region"        = "ap-northeast-2"
              "awslogs-stream-prefix" = "ecs-exporter"
            }
          }
          readonlyRootFilesystem = true
        },
      ] : []
    )
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
  command              = each.value.command
  health_check         = each.value.health_check
  sidecars             = local.sidecars[each.key]

  tags = {
    Environment = "dev"
    Service     = each.key
    Version     = "v2"
  }
}
