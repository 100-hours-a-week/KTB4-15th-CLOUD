# ---------------------------------------------------------------
# dev ALB 액세스 로그 → CloudWatch Logs (vended logs) → 구독 → Loki
# - dev는 트래픽이 적어 CloudWatch 비용이 작고, Grafana에서 앱 로그와 함께 본다.
#   (prod ALB 액세스 로그는 비용 때문에 S3 직행 예정)
# - aws_lb의 access_logs 블록은 S3 전용이라, CloudWatch Logs delivery 리소스를 쓴다.
# - 형식 JSON: Loki에서 | json으로 필드(elb_status_code 등)를 바로 쓸 수 있다.
# - 로그 그룹 경로에 /alb/가 있어 Alloy가 source="alb" 레이블을 붙인다.
# - 헬스 체크 로그와 연결 로그(TLS 정보)는 쓰지 않아 제외한다.
# ---------------------------------------------------------------
resource "aws_cloudwatch_log_group" "alb_access" {
  name              = "/lookddak/dev/v2/alb/access"
  retention_in_days = 3

  tags = merge(local.common_tags, {
    Name = "lookddak-dev-v2-alb-access"
  })
}

resource "aws_cloudwatch_log_delivery_source" "alb_access" {
  name         = "lookddak-dev-v2-alb-access"
  log_type     = "ALB_ACCESS_LOGS"
  resource_arn = var.alb_arn

  tags = local.common_tags
}

resource "aws_cloudwatch_log_delivery_destination" "alb_access" {
  name                      = "lookddak-dev-v2-alb-access-cwl"
  delivery_destination_type = "CWL"
  output_format             = "json"

  delivery_destination_configuration {
    destination_resource_arn = aws_cloudwatch_log_group.alb_access.arn
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_log_delivery" "alb_access" {
  delivery_source_name     = aws_cloudwatch_log_delivery_source.alb_access.name
  delivery_destination_arn = aws_cloudwatch_log_delivery_destination.alb_access.arn

  tags = local.common_tags
}
