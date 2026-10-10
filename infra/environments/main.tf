module "shared_core" {
  source = "./shared/core"
}

module "prod_v1_database" {
  source = "./prod/v1/database"

  db_subnet_ids        = module.shared_core.db_subnet_ids
  db_security_group_id = module.shared_core.db_security_group_id
}

module "prod_v1_iam" {
  source = "./prod/v1/iam"

  ecr_repository_arns = module.shared_core.ecr_repository_arns
}
