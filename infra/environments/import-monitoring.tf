# ---------------------------------------------------------------
# Discord 알림 Lambda import
# - 적용 후 이 파일은 삭제한다
# ---------------------------------------------------------------

# Lambda (id: 함수 이름)
import {
  to = module.prod_v1_monitoring.aws_lambda_function.discord_alert
  id = "lookddak-discord-alert"
}

# SQS → Lambda 이벤트 소스 매핑 (id: UUID)
import {
  to = module.prod_v1_monitoring.aws_lambda_event_source_mapping.alert_queue
  id = "243729cd-50ee-4651-a36a-8d8f81f47ae1"
}
