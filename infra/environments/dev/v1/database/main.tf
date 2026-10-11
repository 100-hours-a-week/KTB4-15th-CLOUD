# ---------------------------------------------------------------
# V1 dev MySQL (RDS)
# - prod와 같은 modules/rds-mysql·같은 설정을 사용한다. (삭제 보호만 꺼 둠)
# - 마스터 사용자 이름은 prod와 같다.
# - 마스터 비밀번호는 콘솔에서 만든 SSM SecureString을 생성 시점에만 읽어 넣는다.
#   (ephemeral + password_wo: 값이 plan·state에 저장되지 않음)
# ---------------------------------------------------------------
data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

ephemeral "aws_ssm_parameter" "master_password" {
  arn             = "arn:aws:ssm:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:parameter/lookddak/dev/rds/admin/password"
  with_decryption = true
}

module "mysql" {
  source = "../../../../modules/rds-mysql"

  name_prefix = "lookddak-dev"
  environment = "dev"

  subnet_ids               = var.db_subnet_ids
  security_group_ids       = [var.db_security_group_id]
  availability_zone        = "ap-northeast-2a"
  multi_az                 = false
  subnet_group_description = "LookDDak dev RDS private subnets"

  engine_version              = "8.4.11"
  parameter_group_family      = "mysql8.4"
  parameter_group_description = "LookDDak dev MySQL 8.4 parameter group"
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
  # iops·storage_throughput: 400GiB 미만 gp3는 새로 만들 때 지정할 수 없다.
  # 지정하지 않아도 기본 성능이 prod와 같은 3000 IOPS / 125MiB/s로 적용된다.

  master_username            = var.master_username
  master_password_wo         = ephemeral.aws_ssm_parameter.master_password.value
  master_password_wo_version = 1 # 비밀번호를 SSM으로 다시 적용하려면 값을 올린다

  backup_retention_period  = 7
  backup_window            = "18:00-18:30"
  maintenance_window       = "sun:19:00-sun:19:30"
  deletion_protection      = false # dev는 지웠다 다시 만들 수 있도록 끔 (prod: true)
  skip_final_snapshot      = true
  delete_automated_backups = true
}
