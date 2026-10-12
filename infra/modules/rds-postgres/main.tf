# ---------------------------------------------------------------
# RDS PostgreSQL (Subnet Group + Parameter Group + Instance)
# ---------------------------------------------------------------
resource "aws_db_subnet_group" "this" {
  name        = "${var.identifier}-subnet-group"
  description = var.subnet_group_description
  subnet_ids  = var.subnet_ids

  tags = {
    Name        = "${var.identifier}-subnet-group"
    Environment = var.environment
    Service     = "postgresql"
  }
}

resource "aws_db_parameter_group" "this" {
  name        = "${var.identifier}-${var.parameter_group_family}-pg"
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
    Service     = "postgresql"
  }
}

resource "aws_db_instance" "this" {
  identifier     = var.identifier
  db_name        = var.db_name
  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class

  username            = var.master_username
  password_wo         = var.master_password_wo
  password_wo_version = var.master_password_wo_version

  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true

  multi_az               = var.multi_az
  network_type           = "IPV4"
  publicly_accessible    = false
  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = var.security_group_ids

  parameter_group_name = aws_db_parameter_group.this.name
  port                 = 5432

  iam_database_authentication_enabled = false

  backup_retention_period = var.backup_retention_period
  backup_window           = var.backup_window
  maintenance_window      = var.maintenance_window
  copy_tags_to_snapshot   = true

  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : var.final_snapshot_identifier
  delete_automated_backups  = true

  auto_minor_version_upgrade      = false
  monitoring_interval             = 0
  performance_insights_enabled    = false
  enabled_cloudwatch_logs_exports = var.enabled_cloudwatch_logs_exports

  tags = {
    Name        = var.identifier
    Environment = var.environment
    Service     = "postgresql"
  }

  lifecycle {
    ignore_changes = [apply_immediately]

    precondition {
      condition     = var.skip_final_snapshot || var.final_snapshot_identifier != null
      error_message = "final_snapshot_identifier is required when skip_final_snapshot is false."
    }
  }
}
