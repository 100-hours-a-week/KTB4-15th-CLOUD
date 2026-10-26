module "shared_core" {
  source = "./shared/core"
}

module "shared_ecs_taskdef_store" {
  source = "./shared/ecs-taskdef-store"
}

module "prod_v1_network" {
  source = "./prod/v1/network"
}

# 2026-10-19: V1 prod 구 DB(lookddak-prod-mysql) 삭제. 쓰기 대상은 컷오버로 V2 prod MySQL이 됐다.
# - 최종 스냅샷: lookddak-prod-mysql-final-20261019 (수동)
# - 구 DB가 만든 DB Subnet Group은 V2 prod MySQL이 쓰고 있어 prod_v2_database로 옮긴다.
moved {
  from = module.prod_v1_database.module.mysql.aws_db_subnet_group.this[0]
  to   = module.prod_v2_database.aws_db_subnet_group.mysql
}

# rds/* 파라미터는 V1 EC2 Spring 기본 DB_URL과 운영 스크립트가 읽으므로 V2 prod MySQL을 가리킨다.
module "prod_parameter_store" {
  source = "./prod/parameter-store"

  rds_admin_username = "lookddak_admin"
  rds_database       = "lookddak"
  rds_host           = module.prod_v2_database.mysql_address
  rds_port           = 3306
}

module "prod_v1_parameter_store" {
  source = "./prod/v1/parameter-store"
}

module "prod_v1_iam" {
  source = "./prod/v1/iam"

  ecr_repository_arns = module.shared_core.ecr_repository_arns
}

module "prod_v1_edge" {
  source = "./prod/v1/edge"

  zone_id = module.shared_core.route53_zone_id
}

module "prod_v1_monitoring" {
  source = "./prod/v1/monitoring"

  eventbridge_role_arns  = module.prod_v1_iam.eventbridge_role_arns
  discord_alert_role_arn = module.prod_v1_iam.discord_alert_role_arn
}

module "prod_s3" {
  source = "./prod/s3"
}

module "dev_s3" {
  source = "./dev/s3"
}

module "dev_ecr" {
  source = "./dev/ecr"
}

# ---------------------------------------------------------------
# Dev shared network (legacy module address retained for state compatibility)
# ---------------------------------------------------------------
module "dev_v1_network" {
  source = "./dev/v1/network"
}

# 2026-10-19: V1 dev 구 DB(lookddak-dev-mysql) 삭제. 쓰기 대상은 컷오버로 V2 Dev MySQL이 됐다.
# - 최종 스냅샷: lookddak-dev-mysql-final-20261019 (수동)
# - 구 DB가 만든 DB Subnet Group은 V2 Dev MySQL이 쓰고 있어 dev_v2_database로 옮긴다.
moved {
  from = module.dev_v1_database.module.mysql.aws_db_subnet_group.this[0]
  to   = module.dev_v2_database.aws_db_subnet_group.mysql
}

# rds/* 앱 계정 파라미터는 V2 Dev Spring이 읽으며 V2 Dev MySQL을 가리킨다.
module "dev_parameter_store" {
  source = "./dev/parameter-store"

  rds_admin_username = "lookddak_admin"
  rds_database       = "lookddak"
  rds_host           = module.dev_v2_database.mysql_address
  rds_port           = 3306
}

module "dev_v1_iam" {
  source = "./dev/v1/iam"

  ecr_repository_arns = module.dev_ecr.ecr_repository_arns
}

module "dev_v1_edge" {
  source = "./dev/v1/edge"

  zone_id      = module.shared_core.route53_zone_id
  alb_dns_name = module.dev_v2_alb.alb_dns_name
  alb_zone_id  = module.dev_v2_alb.alb_zone_id
}

