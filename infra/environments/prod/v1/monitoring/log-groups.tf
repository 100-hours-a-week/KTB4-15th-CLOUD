# ---------------------------------------------------------------
# 운영 로그 그룹 (V1 Discord 알림 파이프라인)
# - V1 EC2 앱·상태 로그 그룹, 메트릭 필터, 배포 로그는 2026-10-26 V1 롤백 중단으로 삭제했다.
#   V2 앱 로그는 prod/v2/logging, 지표·알람은 Grafana(prod 모니터링 서버)와 V2 SQS 알람을 쓴다.
# ---------------------------------------------------------------

# Discord 알림 Lambda 로그 (보존 기간 무제한)
resource "aws_cloudwatch_log_group" "discord_alert" {
  name = "/aws/lambda/lookddak-discord-alert"
}
