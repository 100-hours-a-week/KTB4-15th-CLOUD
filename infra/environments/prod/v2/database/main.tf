data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

locals {
  database_name      = "lookddak"
  admin_username     = "lookddak_admin"
  app_username       = "lookddak_app"
  migration_username = "lookddak_migration"

  parameter_paths = {
    admin_username     = "/lookddak/prod/v2/postgresql/admin/username"
    admin_password     = "/lookddak/prod/v2/postgresql/admin/password"
    host               = "/lookddak/prod/v2/postgresql/host"
    port               = "/lookddak/prod/v2/postgresql/port"
    database           = "/lookddak/prod/v2/postgresql/database"
    app_username       = "/lookddak/prod/v2/postgresql/app/username"
    app_password       = "/lookddak/prod/v2/postgresql/app/password"
    app_database_url   = "/lookddak/prod/v2/postgresql/app/database-url"
    app_checkpoint_dsn = "/lookddak/prod/v2/postgresql/app/checkpoint-dsn"
    migration_username = "/lookddak/prod/v2/postgresql/migration/username"
    migration_password = "/lookddak/prod/v2/postgresql/migration/password"
    mysql_jdbc_url     = "/lookddak/prod/v2/mysql/jdbc-url"
  }

  secure_parameter_paths = {
    admin_password     = local.parameter_paths.admin_password
    app_password       = local.parameter_paths.app_password
    app_database_url   = local.parameter_paths.app_database_url
    app_checkpoint_dsn = local.parameter_paths.app_checkpoint_dsn
    migration_password = local.parameter_paths.migration_password
  }
}

# The SecureString must be created manually before apply.
# The ephemeral value is passed to RDS through password_wo and is never stored
# in Terraform plan or state.
ephemeral "aws_ssm_parameter" "admin_password" {
  count = var.read_admin_password_from_ssm ? 1 : 0

  arn             = "arn:aws:ssm:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:parameter${local.parameter_paths.admin_password}"
  with_decryption = true
}

locals {
  admin_password_wo = var.read_admin_password_from_ssm ? ephemeral.aws_ssm_parameter.admin_password[0].value : var.admin_password_wo
}

module "postgresql" {
  source = "../../../../modules/rds-postgres"

  identifier  = "lookddak-prod-v2-postgresql"
  environment = "prod"

  subnet_ids               = var.db_subnet_ids
  security_group_ids       = [var.postgresql_security_group_id]
  subnet_group_description = "LookDDak prod V2 PostgreSQL private DB subnets"
  multi_az                 = true

  engine_version              = "16.15"
  parameter_group_family      = "postgres16"
  parameter_group_description = "LookDDak prod V2 PostgreSQL 16 logical replication parameters"
  parameters = [
    { name = "rds.logical_replication", value = "1", apply_method = "pending-reboot" },
    { name = "max_replication_slots", value = "10", apply_method = "pending-reboot" },
    { name = "max_wal_senders", value = "10", apply_method = "pending-reboot" },
    { name = "max_logical_replication_workers", value = "4", apply_method = "pending-reboot" },
    { name = "max_worker_processes", value = "8", apply_method = "pending-reboot" },
    { name = "max_slot_wal_keep_size", value = "2048", apply_method = "immediate" },
  ]

  instance_class        = "db.t4g.small"
  db_name               = local.database_name
  allocated_storage     = 20
  max_allocated_storage = 100

  master_username            = local.admin_username
  master_password_wo         = local.admin_password_wo
  master_password_wo_version = 1

  backup_retention_period   = 14
  backup_window             = "18:00-18:30"
  maintenance_window        = "sun:19:00-sun:19:30"
  deletion_protection       = true
  skip_final_snapshot       = false
  final_snapshot_identifier = "lookddak-prod-v2-postgresql-final"

  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]
}

# ---------------------------------------------------------------
# V2 prod MySQL (V1 MySQL zero-downtime migration target)
# - Created as a same-region read replica of the V1 prod RDS (lookddak-prod-mysql).
#   Data, engine version, DB name, master user and encryption come from the source.
#   Snapshot start briefly pauses I/O on the Single-AZ source.
# - Steps (same as dev, lookddak_infra/work/v1-mysql-migration/진행기록.md)
#   0) on the source: binlog retention hours 72 (before apply)
#   1) apply as is -> read replica
#   2) on V2 MySQL: init-replication.sh prod stop -> record the start position
#      (2026-10-19 17:03 KST: mysql-bin-changelog.008051:545)
#   3) mysql_promote = true -> apply (promote only; no other RDS change in the same apply)
#   4) init-replication.sh prod start -> external replication from the source
#   5) mysql_read_only = false right before the cutover (separate apply)
# - read_only = 1 is pinned because the replica default (on only while it is a replica)
#   would open writes at promotion. V2 prod Spring already points at this DB's JDBC URL,
#   so read_only must stay on until the cutover.
# ---------------------------------------------------------------
locals {
  mysql_promote   = true  # true: promoted to a standalone instance (start position recorded before promotion)
  mysql_read_only = true  # true: application writes blocked (replication threads ignore read_only)
}

module "mysql" {
  source = "../../../../modules/rds-mysql"

  name_prefix = "lookddak-prod-v2"
  environment = "prod"

  # Read replica of the V1 prod RDS. Becomes standalone when mysql_promote = true.
  replicate_source_db = local.mysql_promote ? null : var.v1_mysql_identifier

  # Same-region replicas use the source Subnet Group (lookddak-prod-db-subnet-group).
  # When the V1 prod RDS is deleted, move that Subnet Group here (see dev cutover, #216).
  create_subnet_group = false
  security_group_ids  = [var.mysql_security_group_id]
  multi_az            = true

  parameter_group_family      = "mysql8.4"
  parameter_group_description = "LookDDak prod V2 MySQL 8.4 parameter group"
  parameters = [
    # Same values as the V1 prod RDS (prod/v1/database)
    { name = "character_set_server", value = "utf8mb4" },
    { name = "collation_server", value = "utf8mb4_0900_ai_ci" },
    { name = "log_output", value = "FILE" },
    { name = "long_query_time", value = "2" },
    { name = "require_secure_transport", value = "1" },
    { name = "slow_query_log", value = "1" },
    { name = "time_zone", value = "UTC" },
    # Block application writes until the cutover
    { name = "read_only", value = local.mysql_read_only ? "1" : "0" },
  ]

  instance_class        = "db.t4g.medium"
  allocated_storage     = 20
  max_allocated_storage = 50

  # Keep automated backups so binlog stays on after promotion (rollback replication source).
  backup_retention_period  = 7
  backup_window            = "18:00-18:30"
  maintenance_window       = "sun:19:00-sun:19:30"
  deletion_protection      = true
  skip_final_snapshot      = true
  delete_automated_backups = true
}
