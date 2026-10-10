# ---------------------------------------------------------------
# V1 EC2 애플리케이션 로그 그룹 (CloudWatch Agent가 수집)
# ---------------------------------------------------------------
locals {
  app_log_groups = toset([
    "/lookddak/prod/nginx",
    "/lookddak/prod/spring",
    "/lookddak/prod/fastapi",
    "/lookddak/prod/nextjs",
    "/lookddak/prod/postgresql",
    "/lookddak/prod/status",
  ])
}

resource "aws_cloudwatch_log_group" "app" {
  for_each = local.app_log_groups

  name              = each.value
  retention_in_days = 30
}

# 배포 스크립트 로그 (보존 기간 무제한)
resource "aws_cloudwatch_log_group" "deploy" {
  name = "/lookddak/deploy"
}

# Discord 알림 Lambda 로그 (보존 기간 무제한)
resource "aws_cloudwatch_log_group" "discord_alert" {
  name = "/aws/lambda/lookddak-discord-alert"
}

# ---------------------------------------------------------------
# 메트릭 필터: 로그에서 숫자를 뽑아 커스텀 지표로 만든다 (알람의 입력)
# ---------------------------------------------------------------

# nginx 접근 로그 → Nginx/ApiServerErrorCount, Nginx/ApiRequestCount
resource "aws_cloudwatch_log_metric_filter" "nginx_5xx" {
  name           = "nginx-api-5xx-count"
  log_group_name = aws_cloudwatch_log_group.app["/lookddak/prod/nginx"].name
  pattern        = "[ip, ident, user, timestamp, request = \"*\", status >= 500, ...]"

  metric_transformation {
    name          = "ApiServerErrorCount"
    namespace     = "Nginx"
    value         = "1"
    default_value = "0"
    unit          = "Count"
  }
}

resource "aws_cloudwatch_log_metric_filter" "nginx_requests" {
  name           = "nginx-api-request-count"
  log_group_name = aws_cloudwatch_log_group.app["/lookddak/prod/nginx"].name
  pattern        = "[ip, ident, user, timestamp, request = \"*\", status >= 100, ...]"

  metric_transformation {
    name          = "ApiRequestCount"
    namespace     = "Nginx"
    value         = "1"
    default_value = "0"
    unit          = "Count"
  }
}

# EC2 상태 수집 로그(JSON) → lookddak-v1-ec2/*
resource "aws_cloudwatch_log_metric_filter" "containers_down" {
  name           = "container-down-count"
  log_group_name = aws_cloudwatch_log_group.app["/lookddak/prod/status"].name
  pattern        = "{ $.containers_down >= 0 }"

  metric_transformation {
    name      = "ContainersDown"
    namespace = "lookddak-v1-ec2"
    value     = "$.containers_down"
    unit      = "Count"
  }
}

resource "aws_cloudwatch_log_metric_filter" "container_mem_max" {
  name           = "container-mem-max-percent"
  log_group_name = aws_cloudwatch_log_group.app["/lookddak/prod/status"].name
  pattern        = "{ $.container_mem_max >= 0 }"

  metric_transformation {
    name      = "ContainerMemMaxPercent"
    namespace = "lookddak-v1-ec2"
    value     = "$.container_mem_max"
    unit      = "Percent"
  }
}

resource "aws_cloudwatch_log_metric_filter" "host_mem" {
  name           = "host-mem-percent"
  log_group_name = aws_cloudwatch_log_group.app["/lookddak/prod/status"].name
  pattern        = "{ $.host_mem >= 0 }"

  metric_transformation {
    name      = "HostMemPercent"
    namespace = "lookddak-v1-ec2"
    value     = "$.host_mem"
    unit      = "Percent"
  }
}
