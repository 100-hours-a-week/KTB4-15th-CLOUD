# ---------------------------------------------------------------
# V3 dev (EKS)
# - 기존 dev VPC를 쓰고, 새 리소스는 dev/v3에만 둔다 (V1/V2 파일과 충돌 방지).
# ---------------------------------------------------------------
locals {
  dev_v3_cluster_name = "lookddak-dev"
}

module "dev_v3_network" {
  source = "./dev/v3/network"

  vpc_id         = module.dev_v1_network.vpc_id
  cluster_name   = local.dev_v3_cluster_name
  nat_gateway_id = module.dev_v2_network.nat_gateway_id
}

module "dev_v3_eks" {
  source = "./dev/v3/eks"

  cluster_name = local.dev_v3_cluster_name
  subnet_ids   = module.dev_v3_network.node_subnet_ids

  admin_principal_arns = [
    "arn:aws:iam::686496667254:user/lookddak-infra-cli",
  ]

  view_principal_arns = [
    "arn:aws:iam::686496667254:role/gha-terraform-plan-role",
  ]
}

module "dev_v3_iam" {
  source = "./dev/v3/iam"

  cluster_name      = local.dev_v3_cluster_name
  oidc_provider_arn = module.dev_v3_eks.oidc_provider_arn
  oidc_issuer       = module.dev_v3_eks.oidc_issuer
}

# 클러스터 안 설치 (helm provider: providers.tf)
module "dev_v3_cilium" {
  source = "./dev/v3/cilium"

  cluster_endpoint  = module.dev_v3_eks.cluster_endpoint
  operator_role_arn = module.dev_v3_iam.cilium_operator_role_arn
}
