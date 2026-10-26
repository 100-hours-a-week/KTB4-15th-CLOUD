# ---------------------------------------------------------------
# ecs_exporter scrape: Prometheus(Monitoring EC2) → ECS Task IP:9779
# - 사이드카 정의는 dev/v2/task-definitions에 있다 (nextjs, spring, fastapi).
# - Prometheus가 ECS API로 RUNNING Task를 찾아 Task IP로 직접 scrape한다.
# ---------------------------------------------------------------
resource "aws_vpc_security_group_egress_rule" "to_ecs_exporter" {
  for_each = var.ecs_task_security_group_ids

  security_group_id            = aws_security_group.this.id
  description                  = "ecs_exporter on ${each.key} tasks"
  ip_protocol                  = "tcp"
  from_port                    = 9779
  to_port                      = 9779
  referenced_security_group_id = each.value
}

resource "aws_vpc_security_group_ingress_rule" "ecs_exporter_from_monitoring" {
  for_each = var.ecs_task_security_group_ids

  security_group_id            = each.value
  description                  = "ecs_exporter scrape from the monitoring server"
  ip_protocol                  = "tcp"
  from_port                    = 9779
  to_port                      = 9779
  referenced_security_group_id = aws_security_group.this.id
}
