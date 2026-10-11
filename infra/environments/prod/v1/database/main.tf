# ---------------------------------------------------------------
# V1 운영 MySQL (RDS)
# - 리소스 정의는 modules/rds-mysql, 여기서는 운영 환경 값만 넣는다.
# ---------------------------------------------------------------
module "mysql" {
  source = "../../../../modules/rds-mysql"

  name_prefix = "lookddak-prod"
  environment = "prod"

  subnet_ids               = var.db_subnet_ids
  security_group_ids       = [var.db_security_group_id]
  availability_zone        = "ap-northeast-2a"
  multi_az                 = false
  subnet_group_description = "LookDDak production RDS private subnets"

  engine_version              = "8.4.11"
  parameter_group_family      = "mysql8.4"
  parameter_group_description = "LookDDak production MySQL 8.4 parameter group"
  parameters = [
    { name = "character_set_server", value = "utf8mb4" },
    { name = "collation_server", value = "utf8mb4_0900_ai_ci" },
    { name = "log_output", value = "FILE" },
    { name = "long_query_time", value = "2" },
    { name = "require_secure_transport", value = "1" },
    { name = "slow_query_log", value = "1" },
    { name = "time_zone", value = "UTC" },
  ]

  instance_class        = "db.t4g.micro"
  db_name               = "lookddak"
  allocated_storage     = 20
  max_allocated_storage = 50
  iops                  = 3000
  storage_throughput    = 125

  backup_retention_period  = 7
  backup_window            = "18:00-18:30"
  maintenance_window       = "sun:19:00-sun:19:30"
  deletion_protection      = true
  skip_final_snapshot      = true
  delete_automated_backups = true
}
