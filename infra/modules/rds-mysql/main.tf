# ---------------------------------------------------------------
# RDS MySQL (Subnet Group + Parameter Group + Instance)
# - prod/v1/database, dev/v1/database에서 환경별 값만 넣어 사용한다.
# - 이 모듈에는 lifecycle prevent_destroy를 두지 않는다 (변수로 켜고 끌 수 없음).
#   운영 DB 보호는 deletion_protection = true(AWS 측 삭제 거부)로 한다.
# - replicate_source_db를 지정하면 같은 리전 리드 레플리카로 만든다.
#   (데이터·엔진 버전·DB 이름·마스터 계정은 원본에서 물려받으므로 지정하지 않는다)
#   이 값을 null로 바꾸고 apply하면 레플리카가 독립 인스턴스로 승격된다.
# ---------------------------------------------------------------
locals {
  # mysql8.4 → mysql84
  parameter_group_suffix = replace(var.parameter_group_family, ".", "")

  is_replica = var.replicate_source_db != null
}

# 같은 리전 리드 레플리카는 원본의 Subnet Group을 그대로 쓰므로(API가 지정을 거부)
# create_subnet_group = false로 두고 만들지 않는다.
# (count 추가로 기존 주소 aws_db_subnet_group.this는 Terraform이 this[0]으로 자동 이동)
resource "aws_db_subnet_group" "this" {
  count = var.create_subnet_group ? 1 : 0

  name        = "${var.name_prefix}-db-subnet-group"
  description = var.subnet_group_description
  subnet_ids  = var.subnet_ids

  tags = {
    Name        = "${var.name_prefix}-db-subnet-group"
    Environment = var.environment
  }
}

resource "aws_db_parameter_group" "this" {
  name        = "${var.name_prefix}-${local.parameter_group_suffix}-pg"
  family      = var.parameter_group_family
  description = var.parameter_group_description

  dynamic "parameter" {
    for_each = var.parameters

    content {
      name         = parameter.value.name
      value        = parameter.value.value
      apply_method = parameter.value.apply_method
    }
  }

  tags = {
    Environment = var.environment
    Service     = "mysql"
  }
}

resource "aws_db_instance" "this" {
  identifier          = "${var.name_prefix}-mysql"
  replicate_source_db = var.replicate_source_db

  db_name        = var.db_name
  engine         = local.is_replica ? null : "mysql"
  engine_version = var.engine_version
  instance_class = var.instance_class

  username                    = var.master_username
  password_wo                 = var.master_password_wo
  password_wo_version         = var.master_password_wo_version
  manage_master_user_password = var.manage_master_user_password

  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = "gp3"
  iops                  = var.iops
  storage_throughput    = var.storage_throughput
  storage_encrypted     = true

  availability_zone      = var.availability_zone
  multi_az               = var.multi_az
  network_type           = "IPV4"
  publicly_accessible    = false
  db_subnet_group_name   = var.create_subnet_group ? aws_db_subnet_group.this[0].name : null
  vpc_security_group_ids = var.security_group_ids

  parameter_group_name = aws_db_parameter_group.this.name
  option_group_name    = var.option_group_name

  port                                = 3306
  iam_database_authentication_enabled = false
  ca_cert_identifier                  = "rds-ca-rsa2048-g1"

  backup_retention_period = var.backup_retention_period
  backup_window           = var.backup_window
  maintenance_window      = var.maintenance_window
  copy_tags_to_snapshot   = true
  skip_final_snapshot     = var.skip_final_snapshot

  auto_minor_version_upgrade = false
  deletion_protection        = var.deletion_protection
  delete_automated_backups   = var.delete_automated_backups
  dedicated_log_volume       = false
  engine_lifecycle_support   = "open-source-rds-extended-support"

  monitoring_interval             = 0
  performance_insights_enabled    = false
  enabled_cloudwatch_logs_exports = ["error", "slowquery"]

  tags = {
    Name        = "${var.name_prefix}-mysql"
    Environment = var.environment
    Service     = "mysql"
  }

  lifecycle {
    ignore_changes = [apply_immediately]
  }
}
