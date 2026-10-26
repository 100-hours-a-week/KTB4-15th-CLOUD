# ---------------------------------------------------------------
# DB exporter: mysqld_exporter, postgres_exporter (Monitoring EC2 컨테이너) → RDS
# - RDS에는 exporter를 설치할 수 없어 Monitoring EC2에서 DB로 접속해 지표를 읽는다.
# - 접속 계정은 DB 안에서 직접 만든다 (읽기 전용, 비밀번호는 SSM SecureString).
# ---------------------------------------------------------------
locals {
  db_exporter_targets = {
    mysql = {
      security_group_id = var.mysql_security_group_id
      port              = 3306
    }
    postgresql = {
      security_group_id = var.postgresql_security_group_id
      port              = 5432
    }
  }
}

resource "aws_vpc_security_group_egress_rule" "to_db" {
  for_each = local.db_exporter_targets

  security_group_id            = aws_security_group.this.id
  description                  = "${each.key} exporter to RDS"
  ip_protocol                  = "tcp"
  from_port                    = each.value.port
  to_port                      = each.value.port
  referenced_security_group_id = each.value.security_group_id
}

resource "aws_vpc_security_group_ingress_rule" "db_from_monitoring" {
  for_each = local.db_exporter_targets

  security_group_id            = each.value.security_group_id
  description                  = "${each.key} exporter from the monitoring server"
  ip_protocol                  = "tcp"
  from_port                    = each.value.port
  to_port                      = each.value.port
  referenced_security_group_id = aws_security_group.this.id
}
