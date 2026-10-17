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
