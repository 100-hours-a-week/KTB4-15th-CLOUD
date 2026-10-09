resource "aws_db_subnet_group" "mysql" {
  name        = "lookddak-prod-db-subnet-group"
  description = "LookDDak production RDS private subnets"
  subnet_ids  = var.db_subnet_ids

  tags = {
    Name        = "lookddak-prod-db-subnet-group"
    Environment = "prod"
  }

  lifecycle {
    ignore_changes = [tags, tags_all]
  }
}

resource "aws_db_parameter_group" "mysql" {
  name        = "lookddak-prod-mysql84-pg"
  family      = "mysql8.4"
  description = "LookDDak production MySQL 8.4 parameter group"

  parameter {
    name         = "character_set_server"
    value        = "utf8mb4"
    apply_method = "immediate"
  }

  parameter {
    name         = "collation_server"
    value        = "utf8mb4_0900_ai_ci"
    apply_method = "immediate"
  }

  parameter {
    name         = "log_output"
    value        = "FILE"
    apply_method = "immediate"
  }

  parameter {
    name         = "long_query_time"
    value        = "2"
    apply_method = "immediate"
  }

  parameter {
    name         = "require_secure_transport"
    value        = "1"
    apply_method = "immediate"
  }

  parameter {
    name         = "slow_query_log"
    value        = "1"
    apply_method = "immediate"
  }

  parameter {
    name         = "time_zone"
    value        = "UTC"
    apply_method = "immediate"
  }

  tags = {
    Environment = "prod"
    Service     = "mysql"
  }

  lifecycle {
    ignore_changes = [tags, tags_all]
  }
}

resource "aws_db_instance" "mysql" {
  identifier     = "lookddak-prod-mysql"
  db_name        = "lookddak"
  engine         = "mysql"
  engine_version = "8.4.11"
  instance_class = "db.t4g.micro"

  allocated_storage     = 20
  max_allocated_storage = 50
  storage_type          = "gp3"
  iops                  = 3000
  storage_throughput    = 125
  storage_encrypted     = true

  availability_zone    = "ap-northeast-2a"
  multi_az             = false
  network_type         = "IPV4"
  publicly_accessible  = false
  db_subnet_group_name = aws_db_subnet_group.mysql.name
  vpc_security_group_ids = [
    var.db_security_group_id,
  ]

  parameter_group_name = aws_db_parameter_group.mysql.name
  option_group_name    = "default:mysql-8-4"

  port                                = 3306
  iam_database_authentication_enabled = false
  ca_cert_identifier                  = "rds-ca-rsa2048-g1"

  backup_retention_period = 7
  backup_window           = "18:00-18:30"
  maintenance_window      = "sun:19:00-sun:19:30"
  copy_tags_to_snapshot   = true
  skip_final_snapshot     = true

  auto_minor_version_upgrade = false
  deletion_protection        = true
  delete_automated_backups   = true
  dedicated_log_volume       = false
  engine_lifecycle_support   = "open-source-rds-extended-support"

  monitoring_interval             = 0
  performance_insights_enabled    = false
  enabled_cloudwatch_logs_exports = ["error", "slowquery"]

  tags = {
    Name        = "lookddak-prod-mysql"
    Environment = "prod"
    Service     = "mysql"
  }

  lifecycle {
    prevent_destroy = true
    ignore_changes  = [apply_immediately, tags, tags_all]
  }
}
