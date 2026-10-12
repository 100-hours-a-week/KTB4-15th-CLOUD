# ---------------------------------------------------------------
# V1 dev 로그 그룹 (로그 수집만, 알림 없음)
# - 컨테이너 로그: docker-compose.dev.yaml의 awslogs 드라이버가 전송
# - 배포 로그: dev CD가 SSM Run Command 출력을 저장
# - prod와 달리 메트릭 필터·알람·상태 로그(/status)는 두지 않는다.
# ---------------------------------------------------------------
locals {
  # 로그 그룹 이름 => Service 태그 값
  log_groups = {
    "/lookddak/dev/nginx"      = "nginx"
    "/lookddak/dev/spring"     = "spring"
    "/lookddak/dev/fastapi"    = "fastapi"
    "/lookddak/dev/nextjs"     = "nextjs"
    "/lookddak/dev/postgresql" = "postgresql"
    "/lookddak/dev/deploy"     = "deploy"
  }
}

resource "aws_cloudwatch_log_group" "this" {
  for_each = local.log_groups

  name              = each.key
  retention_in_days = 30

  tags = {
    Environment = "dev"
    Service     = each.value
  }
}
