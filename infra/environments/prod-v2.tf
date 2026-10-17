# ---------------------------------------------------------------
# V2 prod network foundation
# - Reuse the V1 prod VPC, existing Public 2a subnet, and Internet Gateway.
# - Create only the additional subnets, NAT Gateway, and routing required by V2.
# ---------------------------------------------------------------
module "prod_v2_network" {
  source = "./prod/v2/network"

  vpc_id                     = module.prod_v1_network.vpc_id
  existing_public_subnet_id  = module.prod_v1_network.public_subnet_ids[0]
  prod_app_security_group_id = module.prod_v1_network.app_security_group_id
}
