data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

locals {
  database_name      = "lookddak"
  admin_username     = "lookddak_admin"
  app_username       = "lookddak_app"
  migration_username = "lookddak_migration"

  parameter_paths = {
    admin_username     = "/lookddak/dev/v2/postgresql/admin/username"
    admin_password     = "/lookddak/dev/v2/postgresql/admin/password"
    host               = "/lookddak/dev/v2/postgresql/host"
    port               = "/lookddak/dev/v2/postgresql/port"
    database           = "/lookddak/dev/v2/postgresql/database"
    app_username       = "/lookddak/dev/v2/postgresql/app/username"
    app_password       = "/lookddak/dev/v2/postgresql/app/password"
    migration_username = "/lookddak/dev/v2/postgresql/migration/username"
    migration_password = "/lookddak/dev/v2/postgresql/migration/password"
  }

  secure_parameter_paths = {
    admin_password     = local.parameter_paths.admin_password
    app_password       = local.parameter_paths.app_password
    migration_password = local.parameter_paths.migration_password
  }
}

# The SecureString must be created manually before plan/apply.
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

  identifier  = "lookddak-dev-postgresql"
  environment = "dev"

  subnet_ids               = var.db_subnet_ids
  security_group_ids       = [var.postgresql_security_group_id]
  subnet_group_description = "LookDDak dev V2 PostgreSQL private DB subnets"
  multi_az                 = true

  engine_version              = "16.15"
  parameter_group_family      = "postgres16"
  parameter_group_description = "LookDDak dev V2 PostgreSQL 16 logical replication parameters"
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

  backup_retention_period   = 7
  backup_window             = "18:00-18:30"
  maintenance_window        = "sun:19:00-sun:19:30"
  deletion_protection       = true
  skip_final_snapshot       = false
  final_snapshot_identifier = "lookddak-dev-postgresql-final"

  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]
}

# ---------------------------------------------------------------
# V2 dev MySQL (V1 MySQL zero-downtime migration target)
# - Created as a same-region read replica of the existing dev RDS (lookddak-dev-mysql).
#   Data, engine version, DB name, master user and encryption come from the source.
# - Steps (see lookddak_infra/work/v1-mysql-migration/진행기록.md)
#   1) apply as is -> read replica (brief I/O pause on the Single-AZ source at snapshot start)
#      set binlog retention hours on the source before apply
#   2) on V2 MySQL: rds_stop_replication -> record the replication start position
#      (Relay_Source_Log_File, Exec_Source_Log_Pos from SHOW REPLICA STATUS)
#   3) mysql_promote = true -> apply -> promoted to a standalone instance
#   4) on V2 MySQL: rds_set_external_source(..., that file/position, ssl 1) -> rds_start_replication
# - read_only = 1 is pinned in the parameter group because the replica default
#   (on only while it is a replica) would open writes at promotion.
#   Set mysql_read_only = false right before the cutover.
#   dev: kept false during cutover/rollback rehearsals (2026-10-14~). Application writes reach
#   this DB only when ProxySQL routes to it; replication threads ignore read_only.
# ---------------------------------------------------------------
locals {
  mysql_promote   = true # true: promote the read replica (after recording the start position)
  mysql_read_only = false # false: writes allowed (kept 0 during dev cutover rehearsals; ProxySQL decides the write target)
}

module "mysql" {
  source = "../../../../modules/rds-mysql"

  name_prefix = "lookddak-dev-v2"
  environment = "dev"

  # Read replica of the existing dev RDS. Becomes standalone when mysql_promote = true.
  replicate_source_db = local.mysql_promote ? null : var.v1_mysql_identifier

  # Same-region replicas use the source Subnet Group (lookddak-dev-db-subnet-group).
  create_subnet_group = false
  security_group_ids  = [var.mysql_security_group_id]
  availability_zone   = "ap-northeast-2a"
  multi_az            = false

  parameter_group_family      = "mysql8.4"
  parameter_group_description = "LookDDak dev V2 MySQL 8.4 parameter group"
  parameters = [
    # Same values as the existing dev RDS (dev/v1/database)
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
  deletion_protection      = false
  skip_final_snapshot      = true
  delete_automated_backups = true
}
