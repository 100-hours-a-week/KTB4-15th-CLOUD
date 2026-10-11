# ---------------------------------------------------------------
# V2 dev (migration rehearsal / staging)
# - Reuse only the VPC and existing Public 2a subnet from V1 dev.
# - Keep every new V2 resource in dev/v2 to avoid V1 file conflicts.
# ---------------------------------------------------------------
module "dev_v2_network" {
  source = "./dev/v2/network"

  vpc_id                    = module.dev_v1_network.vpc_id
  existing_public_subnet_id = module.dev_v1_network.public_subnet_ids[0]
}
