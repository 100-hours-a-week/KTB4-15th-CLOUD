# ---------------------------------------------------------------
# ECS Task Definition 템플릿 (S3 객체)
# - Terraform은 revision을 등록하지 않는다. 템플릿만 S3에 올린다.
# - CI가 템플릿의 __DIGEST__를 이번 빌드 이미지 digest로 바꿔
#   register-task-definition에 그대로 넘긴다.
# - 템플릿이 바뀌면 plan에 content diff로 보인다 (설정 변경 리뷰).
# ---------------------------------------------------------------
locals {
  container_definition = merge(
    {
      name      = var.container_name
      image     = "${var.image_repository_url}@__DIGEST__"
      essential = true

      environment = [
        for name in sort(keys(var.environment)) : { name = name, value = var.environment[name] }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = var.log_group_name
          "awslogs-region"        = var.log_region
          "awslogs-stream-prefix" = "ecs"
        }
      }

      privileged             = false
      readonlyRootFilesystem = false
    },
    length(var.port_mappings) == 0 ? {} : {
      portMappings = [
        for port in var.port_mappings : {
          name          = port.name
          containerPort = port.container_port
          hostPort      = port.container_port
          protocol      = "tcp"
          appProtocol   = port.app_protocol
        }
      ]
    },
    length(var.secrets) == 0 ? {} : {
      secrets = [
        for name in sort(keys(var.secrets)) : { name = name, valueFrom = var.secrets[name] }
      ]
    },
    var.command == null ? {} : {
      command = var.command
    },
    var.health_check == null ? {} : {
      healthCheck = {
        command     = var.health_check.command
        interval    = var.health_check.interval
        timeout     = var.health_check.timeout
        retries     = var.health_check.retries
        startPeriod = var.health_check.start_period
      }
    },
  )

  task_definition = {
    family                  = var.family
    taskRoleArn             = var.task_role_arn
    executionRoleArn        = var.execution_role_arn
    networkMode             = "awsvpc"
    requiresCompatibilities = ["FARGATE"]
    cpu                     = tostring(var.cpu)
    memory                  = tostring(var.memory)

    runtimePlatform = {
      operatingSystemFamily = "LINUX"
      cpuArchitecture       = var.cpu_architecture
    }

    # 앱 컨테이너가 항상 첫 번째. 사이드카(ecs_exporter, Fluent Bit 등)는 뒤에 붙인다.
    # 앱 CD는 앱 컨테이너를 이름(container_name)으로 찾아 image digest만 바꾼다.
    containerDefinitions = concat([local.container_definition], var.sidecars)

    tags = [
      for key in sort(keys(var.tags)) : { key = key, value = var.tags[key] }
    ]
  }
}

resource "aws_s3_object" "this" {
  bucket       = var.bucket_name
  key          = var.s3_key
  content      = jsonencode(local.task_definition)
  content_type = "application/json"
}
