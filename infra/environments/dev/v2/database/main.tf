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
    app_database_url   = "/lookddak/dev/v2/postgresql/app/database-url"
    app_checkpoint_dsn = "/lookddak/dev/v2/postgresql/app/checkpoint-dsn"
    migration_username = "/lookddak/dev/v2/postgresql/migration/username"
    migration_password = "/lookddak/dev/v2/postgresql/migration/password"
    mysql_jdbc_url     = "/lookddak/dev/v2/mysql/jdbc-url"
  }

  secure_parameter_paths = {
    admin_password     = local.parameter_paths.admin_password
    app_password       = local.parameter_paths.app_password
    app_database_url   = local.parameter_paths.app_database_url
    app_checkpoint_dsn = local.parameter_paths.app_checkpoint_dsn
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
    # 모든 쿼리 기록 (db-log-tailer가 RDS API로 읽어 Loki로 보낸다). 둘 다 동적 파라미터라 재부팅 없음
    # - log_statement=all: 받은 쿼리 원문과 바인드 값(DETAIL: parameters)
    # - log_duration=on: 끝난 쿼리마다 실행 시간 (실패하면 ERROR 줄)
    { name = "log_statement", value = "all", apply_method = "immediate" },
    { name = "log_duration", value = "1", apply_method = "immediate" },
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

  # postgresql 로그는 CloudWatch로 내보내지 않는다 (모든 쿼리를 기록해서 비용이 크다).
  # db-log-tailer가 RDS API로 로그 파일을 읽어 Alloy → Loki로 보낸다 (modules/observability/db-query-log.tf).
  enabled_cloudwatch_logs_exports = ["upgrade"]
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
# - dev rebuild (2026-10-19): V2 Spring wrote to this DB directly while read_only = 0 (split-brain).
#   1) mysql_enabled = false -> apply (delete, #199)  2) mysql_enabled = true -> apply (new read replica)
#   then steps 2)-4) above (start position mysql-bin-changelog.002235:158).
#   read_only = 0 again for the dev cutover rehearsals.
# - dev cutover (2026-10-19): this DB is the write target. The old DB (lookddak-dev-mysql) was deleted
#   after a final snapshot, so the read-replica source is gone (replicate_source_db removed).
#   Recreating this DB (mysql_enabled false -> true) now needs a snapshot restore, not a replica.
# ---------------------------------------------------------------
locals {
  mysql_enabled   = true  # false: V2 MySQL deleted, true: created
  mysql_read_only = false # false: writes allowed (write target since the 2026-10-19 cutover)
}

# Created by the old DB module (lookddak-dev-db-subnet-group) and inherited by the read replica.
# Moved here when the old DB was deleted (root main.tf moved block). Same values, no change.
resource "aws_db_subnet_group" "mysql" {
  name        = "lookddak-dev-db-subnet-group"
  description = "LookDDak dev RDS private subnets"
  subnet_ids  = var.db_subnet_ids

  tags = {
    Name        = "lookddak-dev-db-subnet-group"
    Environment = "dev"
  }
}

moved {
  from = module.mysql
  to   = module.mysql[0]
}

# 모든 쿼리 기록: MariaDB Audit Plugin (RDS MySQL에서 쓸 수 있는 감사 플러그인)
# - 감사 로그(audit/server_audit.log*)는 db-log-tailer가 RDS API로 읽어 Loki로 보낸다 (CloudWatch로 내보내지 않음).
# - 붙일 때 재시작은 없지만 짧은 영향이 있을 수 있다. 떼면 RDS가 재시작한다.
# - rdsadmin(매초 상태 확인), exporter(mysqld_exporter)는 제외한다. CONNECT는 제외 사용자도 기록된다.
resource "aws_db_option_group" "mysql_audit" {
  name                     = "lookddak-dev-v2-mysql84-audit"
  option_group_description = "LookDDak dev V2 MySQL 8.4 audit log (MariaDB Audit Plugin)"
  engine_name              = "mysql"
  major_engine_version     = "8.4"

  option {
    option_name = "MARIADB_AUDIT_PLUGIN"

    option_settings {
      name  = "SERVER_AUDIT_EVENTS"
      value = "CONNECT,QUERY"
    }
    option_settings {
      name  = "SERVER_AUDIT_EXCL_USERS"
      value = "rdsadmin,exporter"
    }
    # 쿼리 원문 길이 상한 (기본 1024자에서 늘림)
    option_settings {
      name  = "SERVER_AUDIT_QUERY_LOG_LIMIT"
      value = "65536"
    }
    # 100MB × 10개 (기본 1MB × 9개는 수집기가 따라잡기 전에 회전될 수 있다)
    option_settings {
      name  = "SERVER_AUDIT_FILE_ROTATE_SIZE"
      value = "100000000"
    }
    option_settings {
      name  = "SERVER_AUDIT_FILE_ROTATIONS"
      value = "10"
    }
  }

  tags = {
    Name        = "lookddak-dev-v2-mysql84-audit"
    Environment = "dev"
    Version     = "v2"
  }
}

module "mysql" {
  source = "../../../../modules/rds-mysql"
  count  = local.mysql_enabled ? 1 : 0

  name_prefix = "lookddak-dev-v2"
  environment = "dev"

  # Uses lookddak-dev-db-subnet-group (aws_db_subnet_group.mysql above), inherited from the old DB.
  create_subnet_group = false
  security_group_ids  = [var.mysql_security_group_id]
  availability_zone   = "ap-northeast-2a"
  multi_az            = false

  parameter_group_family      = "mysql8.4"
  parameter_group_description = "LookDDak dev V2 MySQL 8.4 parameter group"
  option_group_name           = aws_db_option_group.mysql_audit.name
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

  # error·slowquery 로그는 db-log-tailer가 RDS API로 읽어 Alloy → Loki로 보낸다 (CloudWatch로 내보내지 않음).
  # 모듈이 apply_immediately를 쓰지 않아 다음 유지보수 시간에 반영된다. 바로 끄려면 CLI --apply-immediately.
  enabled_cloudwatch_logs_exports = []
}
