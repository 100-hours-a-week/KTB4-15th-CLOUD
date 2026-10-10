# 모니터링 import 블록
# apply로 state에 편입된 뒤에는 이 파일을 삭제한다.

# ---------------------------------------------------------------
# Log Group (id: 로그 그룹 이름)
# ---------------------------------------------------------------
import {
  to = module.prod_v1_monitoring.aws_cloudwatch_log_group.app["/lookddak/prod/nginx"]
  id = "/lookddak/prod/nginx"
}

import {
  to = module.prod_v1_monitoring.aws_cloudwatch_log_group.app["/lookddak/prod/spring"]
  id = "/lookddak/prod/spring"
}

import {
  to = module.prod_v1_monitoring.aws_cloudwatch_log_group.app["/lookddak/prod/fastapi"]
  id = "/lookddak/prod/fastapi"
}

import {
  to = module.prod_v1_monitoring.aws_cloudwatch_log_group.app["/lookddak/prod/nextjs"]
  id = "/lookddak/prod/nextjs"
}

import {
  to = module.prod_v1_monitoring.aws_cloudwatch_log_group.app["/lookddak/prod/postgresql"]
  id = "/lookddak/prod/postgresql"
}

import {
  to = module.prod_v1_monitoring.aws_cloudwatch_log_group.app["/lookddak/prod/status"]
  id = "/lookddak/prod/status"
}

import {
  to = module.prod_v1_monitoring.aws_cloudwatch_log_group.deploy
  id = "/lookddak/deploy"
}

import {
  to = module.prod_v1_monitoring.aws_cloudwatch_log_group.discord_alert
  id = "/aws/lambda/lookddak-discord-alert"
}

# ---------------------------------------------------------------
# Metric Filter (id: 로그그룹이름:필터이름)
# ---------------------------------------------------------------
import {
  to = module.prod_v1_monitoring.aws_cloudwatch_log_metric_filter.nginx_5xx
  id = "/lookddak/prod/nginx:nginx-api-5xx-count"
}

import {
  to = module.prod_v1_monitoring.aws_cloudwatch_log_metric_filter.nginx_requests
  id = "/lookddak/prod/nginx:nginx-api-request-count"
}

import {
  to = module.prod_v1_monitoring.aws_cloudwatch_log_metric_filter.containers_down
  id = "/lookddak/prod/status:container-down-count"
}

import {
  to = module.prod_v1_monitoring.aws_cloudwatch_log_metric_filter.container_mem_max
  id = "/lookddak/prod/status:container-mem-max-percent"
}

import {
  to = module.prod_v1_monitoring.aws_cloudwatch_log_metric_filter.host_mem
  id = "/lookddak/prod/status:host-mem-percent"
}

# ---------------------------------------------------------------
# CloudWatch Alarm (id: 알람 이름)
# ---------------------------------------------------------------
import {
  to = module.prod_v1_monitoring.aws_cloudwatch_metric_alarm.containers_down
  id = "lookddak-containers-down"
}

import {
  to = module.prod_v1_monitoring.aws_cloudwatch_metric_alarm.container_mem_high
  id = "lookddak-container-mem-high"
}

import {
  to = module.prod_v1_monitoring.aws_cloudwatch_metric_alarm.host_mem_high
  id = "lookddak-host-mem-high"
}

import {
  to = module.prod_v1_monitoring.aws_cloudwatch_metric_alarm.nginx_5xx
  id = "lookddak-nginx-5xx-count"
}

import {
  to = module.prod_v1_monitoring.aws_cloudwatch_metric_alarm.nginx_requests
  id = "lookddak-nginx-request-count"
}

import {
  to = module.prod_v1_monitoring.aws_cloudwatch_metric_alarm.alert_dlq_not_empty
  id = "alert-pipeline-dlq-not-empty"
}

# ---------------------------------------------------------------
# EventBridge Rule (id: 규칙 이름)
# ---------------------------------------------------------------
import {
  to = module.prod_v1_monitoring.aws_cloudwatch_event_rule.alert["alarm_state_change"]
  id = "lookddak-alarm-state-change"
}

import {
  to = module.prod_v1_monitoring.aws_cloudwatch_event_rule.alert["aws_health"]
  id = "lookddak-aws-health"
}

import {
  to = module.prod_v1_monitoring.aws_cloudwatch_event_rule.alert["docker_events"]
  id = "lookddak-docker-events"
}

import {
  to = module.prod_v1_monitoring.aws_cloudwatch_event_rule.alert["ec2_state_change"]
  id = "lookddak-ec2-state-change"
}

import {
  to = module.prod_v1_monitoring.aws_cloudwatch_event_rule.alert["rds_events"]
  id = "lookddak-rds-events"
}

# ---------------------------------------------------------------
# EventBridge Target (id: 규칙이름/타깃ID)
# ---------------------------------------------------------------
import {
  to = module.prod_v1_monitoring.aws_cloudwatch_event_target.alert["alarm_state_change"]
  id = "lookddak-alarm-state-change/Id5ebf6260-9768-48e8-8997-990ccc4cb19d"
}

import {
  to = module.prod_v1_monitoring.aws_cloudwatch_event_target.alert["aws_health"]
  id = "lookddak-aws-health/Ida562fc30-dec6-4c51-b2a3-406e63ca6c14"
}

import {
  to = module.prod_v1_monitoring.aws_cloudwatch_event_target.alert["docker_events"]
  id = "lookddak-docker-events/Idbcc7eb30-dd93-4cad-8eb9-d8c9f63d97c9"
}

import {
  to = module.prod_v1_monitoring.aws_cloudwatch_event_target.alert["ec2_state_change"]
  id = "lookddak-ec2-state-change/Ida2188ef3-263c-42f9-b7de-ca0a4cb8a6ca"
}

import {
  to = module.prod_v1_monitoring.aws_cloudwatch_event_target.alert["rds_events"]
  id = "lookddak-rds-events/Id052879a0-9e55-4e57-8b77-51d6420fef3e"
}

# ---------------------------------------------------------------
# SQS (id: 큐 URL)
# ---------------------------------------------------------------
import {
  to = module.prod_v1_monitoring.aws_sqs_queue.alert
  id = "https://sqs.ap-northeast-2.amazonaws.com/686496667254/lookddak-alert-queue"
}

import {
  to = module.prod_v1_monitoring.aws_sqs_queue.alert_dlq
  id = "https://sqs.ap-northeast-2.amazonaws.com/686496667254/lookddak-alert-dlq"
}

# ---------------------------------------------------------------
# SNS (id: 토픽 ARN)
# ---------------------------------------------------------------
import {
  to = module.prod_v1_monitoring.aws_sns_topic.alert_pipeline
  id = "arn:aws:sns:ap-northeast-2:686496667254:lookddak-alert-pipeline"
}

# ---------------------------------------------------------------
# Lambda (id: 함수 이름 / 이벤트 소스 매핑 UUID)
# ---------------------------------------------------------------
import {
  to = module.prod_v1_monitoring.aws_lambda_function.discord_alert
  id = "lookddak-discord-alert"
}

import {
  to = module.prod_v1_monitoring.aws_lambda_event_source_mapping.alert_queue
  id = "243729cd-50ee-4651-a36a-8d8f81f47ae1"
}
