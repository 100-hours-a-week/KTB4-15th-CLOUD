# ---------------------------------------------------------------
# V2 prod Task Definition 템플릿
# - Terraform은 템플릿만 S3(prod/v2/<service>.json)에 올린다.
# - revision 등록은 앱 레포 CD(main merge)가 한다 (템플릿 + 이미지 digest).
# - 이 값을 바꾸고 apply하면 다음 배포부터 반영된다.
# - 값은 기존 정적 JSON(prod/v2/task-definitions/*.json)과 같다 (Spring SSE 8081 포함, #293).
# - 모니터링 사이드카(ecs-exporter, FireLens log-router)는 dev와 같다. 트레이스(otel-init)는 아직 넣지 않는다.
# - crawler는 EventBridge Scheduler(현재 DISABLED)가 family ARN으로 RunTask한다.
# ---------------------------------------------------------------
locals {
  ssm = "/lookddak/prod"

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
        CORS_ALLOWED_ORIGINS            = "https://lookddak.com,https://v2-prod.lookddak.com"
        SENTRY_ENVIRONMENT              = "prod"
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
        DB_USERNAME         = "${local.ssm}/v2/mysql/app/username"
        DB_PASSWORD         = "${local.ssm}/v2/mysql/app/password"
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

      health_check = {
        command      = ["CMD", "python", "-c", "import socket; socket.create_connection(('localhost', 8000), 3).close()"]
        interval     = 30
        timeout      = 5
        retries      = 3
        start_period = 180
      }
    }

    # 가격 갱신 크롤러: dev 템플릿과 같은 구성 (ARM64, --apply).
    # - BE 알림 주소는 DNS 전환 후 V2를 가리키는 lookddak.com.
    # - PRICE_REFRESH_BACKEND_AUTH_HEADERS_JSON SSM은 스케줄 활성화 전에 만든다.
    crawler = {
      cpu    = 1024
      memory = 2048
      environment = {
        PRICE_REFRESH_BACKEND_BASE_URL = "https://lookddak.com"
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
# 모니터링 사이드카 (nextjs, spring, fastapi에만. crawler 배치는 제외) - dev/v2/task-definitions와 같다
# 1) ecs-exporter: Task CPU·메모리·네트워크 → :9779/metrics (prod 모니터링 서버 Prometheus가 수집)
#    Task 메타데이터 엔드포인트(169.254.170.2)를 읽으므로 IAM 권한이 필요 없다.
# 2) log-router: FireLens(aws-for-fluent-bit init 이미지)
#    앱 stdout/stderr → CloudWatch(기존 로그 그룹) + Loki(prod 모니터링 서버 Alloy :3500)
#    Loki 출력·여러 줄 합치기 설정은 S3(fluent_bit_config_arn, fluent_bit_parsers_arn)에서 시작할 때 받는다.
# - 둘 다 essential = false: 죽어도 앱은 계속 돈다 (로그·지표보다 서비스 가용성 우선).
#   단, 앱 컨테이너는 log-router가 시작(START)된 뒤에 뜬다.
# - 템플릿은 다음 앱 배포(main merge CD) 때 반영된다. 앱 CD는 앱 컨테이너를 이름으로 찾는다.
# ---------------------------------------------------------------
locals {
  ecs_exporter_image = "quay.io/prometheuscommunity/ecs-exporter:v0.4.0"
  fluent_bit_image   = "public.ecr.aws/aws-observability/aws-for-fluent-bit:init-2.34.3.20261020"
  monitored_services = ["nextjs", "spring", "fastapi"]

  # 여러 줄 합치기 규칙 (modules/observability/fluent-bit/parsers.conf)
  multiline_parsers = {
    nextjs  = "indented_cont"
    spring  = "ts_start"
    fastapi = "ts_start"
  }

  sidecars = {
    for service in local.monitored_services : service => [
      {
        name              = "ecs-exporter"
        image             = local.ecs_exporter_image
        essential         = false
        command           = ["--web.disable-exporter-metrics"]
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
      {
        name              = "log-router"
        image             = local.fluent_bit_image
        essential         = false
        memoryReservation = 50
        firelensConfiguration = {
          type = "fluentbit"
          options = {
            "enable-ecs-log-metadata" = "true"
          }
        }
        environment = [
          { name = "SERVICE", value = service },
          { name = "MULTILINE_PARSER", value = local.multiline_parsers[service] },
          { name = "aws_fluent_bit_init_s3_1", value = var.fluent_bit_config_arn },
          { name = "aws_fluent_bit_init_s3_2", value = var.fluent_bit_parsers_arn },
        ]
        # log-router 자신의 로그는 awslogs로 (FireLens로 보내면 순환)
        logConfiguration = {
          logDriver = "awslogs"
          options = {
            "awslogs-group"         = var.log_group_names[service]
            "awslogs-region"        = "ap-northeast-2"
            "awslogs-stream-prefix" = "log-router"
          }
        }
      },
    ]
  }

  # 앱 컨테이너 로그: FireLens. options가 출력 1(CloudWatch, 기존 로그 그룹)이 된다.
  app_log_configuration = {
    for service in local.monitored_services : service => {
      logDriver = "awsfirelens"
      options = {
        Name              = "cloudwatch_logs"
        region            = "ap-northeast-2"
        log_group_name    = var.log_group_names[service]
        log_stream_prefix = "ecs/"
        auto_create_group = "false"
        log_key           = "log"
      }
    }
  }
}

module "template" {
  source   = "../../../../modules/ecs-taskdef-template"
  for_each = local.services

  bucket_name = var.bucket_name
  s3_key      = "prod/v2/${each.key}.json"

  family             = "lookddak-prod-v2-${each.key}"
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
  sidecars             = try(local.sidecars[each.key], [])
  log_configuration    = try(local.app_log_configuration[each.key], null)
  depends_on_containers = contains(local.monitored_services, each.key) ? [
    { containerName = "log-router", condition = "START" },
  ] : []

  tags = {
    Environment = "prod"
    Service     = each.key
    Version     = "v2"
  }
}
