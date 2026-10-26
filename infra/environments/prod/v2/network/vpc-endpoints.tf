# ---------------------------------------------------------------
# S3 Gateway Endpoint (private app 서브넷)
# - private app 서브넷에서 S3로 가는 트래픽을 NAT 대신 VPC 안 경로로 보낸다 (dev/v2/network와 같다).
#   Gateway Endpoint는 무료이고, NAT 처리 비용(GB당 과금)이 빠진다.
# - 주 용도: 모니터링 서버 Loki·Tempo ↔ S3. ECS Task의 ECR 이미지 레이어·S3 업로드, lambda-promtail의 ALB 로그 읽기도 이 경로를 탄다.
# - 정책은 기본값(전체 허용). 접근 제어는 각 버킷 정책과 IAM이 한다.
# ---------------------------------------------------------------
data "aws_region" "current" {}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.${data.aws_region.current.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private_app.id]

  tags = {
    Name        = "lookddak-prod-v2-s3-gateway"
    Environment = "prod"
    Version     = "v2"
  }
}
