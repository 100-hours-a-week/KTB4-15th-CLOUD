resource "aws_ecs_cluster" "main" {
  name = "lookddak-prod-v2"

  # Container Insights 끔 (2026-10-26): Task 지표는 ecs-exporter → Prometheus(Grafana)로 본다
  setting {
    name  = "containerInsights"
    value = "disabled"
  }

  tags = {
    Environment = "prod"
    Version     = "v2"
  }
}
