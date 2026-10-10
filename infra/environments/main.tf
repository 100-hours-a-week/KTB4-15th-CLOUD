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

module "prod_v1_compute" {
  source = "./prod/v1/compute"

  subnet_id                 = module.shared_core.public_subnet_ids[0]
  security_group_id         = module.shared_core.app_security_group_id
  iam_instance_profile_name = module.prod_v1_iam.ec2_instance_profile_name
}

module "prod_v1_cicd_deploy_policy" {
  source = "./prod/v1/cicd-deploy-policy"

  deploy_role_names   = module.prod_v1_iam.deploy_role_names
  ecr_repository_arns = module.shared_core.ecr_repository_arns
  ec2_instance_arn    = module.prod_v1_compute.instance_arn
}

module "prod_v1_edge" {
  source = "./prod/v1/edge"

  zone_id       = module.shared_core.route53_zone_id
  app_public_ip = module.prod_v1_compute.public_ip
}

module "prod_s3" {
  source = "./prod/s3"
}

module "dev_s3" {
  source = "./dev/s3"
}
