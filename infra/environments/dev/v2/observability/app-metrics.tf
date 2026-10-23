# ---------------------------------------------------------------
# 앱 메트릭 scrape: Prometheus(Monitoring EC2) → ECS Task IP:<앱 포트>
# - Spring: :8080/actuator/prometheus (Micrometer), FastAPI: :8000/metrics
# - 앱 포트를 그대로 쓴다. ALB는 /api/* 등 정해진 경로만 앱으로 보내므로
#   메트릭 경로는 외부에 노출되지 않는다.
# ---------------------------------------------------------------
locals {
  app_metrics_ports = {
    spring  = 8080
    fastapi = 8000
  }
}

resource "aws_vpc_security_group_egress_rule" "to_app_metrics" {
  for_each = local.app_metrics_ports

  security_group_id            = aws_security_group.this.id
  description                  = "App metrics on ${each.key} tasks"
  ip_protocol                  = "tcp"
  from_port                    = each.value
  to_port                      = each.value
  referenced_security_group_id = var.ecs_task_security_group_ids[each.key]
}

resource "aws_vpc_security_group_ingress_rule" "app_metrics_from_monitoring" {
  for_each = local.app_metrics_ports

  security_group_id            = var.ecs_task_security_group_ids[each.key]
  description                  = "App metrics scrape from the monitoring server"
  ip_protocol                  = "tcp"
  from_port                    = each.value
  to_port                      = each.value
  referenced_security_group_id = aws_security_group.this.id
}
