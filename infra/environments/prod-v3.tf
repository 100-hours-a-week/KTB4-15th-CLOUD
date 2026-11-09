# ---------------------------------------------------------------
# V3 prod (EKS)
# - 기존 Terraform Root·State·CI 경계를 그대로 사용한다.
# - 신규 리소스는 prod/v3 모듈에만 두고 기존 Prod V1/V2 리소스는
#   AWS Data Source로 조회하여 소유권과 State를 이동하지 않는다.
# ---------------------------------------------------------------
locals {
  prod_v3_cluster_name = "lookddak-prod"
}

data "aws_vpc" "prod_v3" {
  filter {
    name   = "tag:Name"
    values = ["lookddak-prod-vpc"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

data "aws_nat_gateway" "prod_v3" {
  vpc_id = data.aws_vpc.prod_v3.id
  state  = "available"

  filter {
    name   = "tag:Name"
    values = ["lookddak-prod-v2-nat"]
  }
}

data "aws_security_group" "prod_v3_api_access" {
  vpc_id = data.aws_vpc.prod_v3.id

  filter {
    name   = "tag:Name"
    values = ["lookddak-prod-monitoring-sg"]
  }
}

data "aws_instances" "prod_v3_api_access" {
  instance_state_names = ["running"]

  filter {
    name   = "tag:Name"
    values = ["lookddak-prod-monitoring"]
  }
}

module "prod_v3_network" {
  source = "./prod/v3/network"

  vpc_id         = data.aws_vpc.prod_v3.id
  cluster_name   = local.prod_v3_cluster_name
  nat_gateway_id = data.aws_nat_gateway.prod_v3.id
}

module "prod_v3_eks" {
  source = "./prod/v3/eks"

  cluster_name = local.prod_v3_cluster_name
  subnet_ids   = module.prod_v3_network.node_subnet_ids

  admin_principal_arns = [
    "arn:aws:iam::686496667254:user/lookddak-infra-cli",
  ]

  api_access_security_group_id = data.aws_security_group.prod_v3_api_access.id
}

output "prod_v3_cluster" {
  description = "Prod V3 EKS Control Plane 접속 정보"
  value = {
    name                    = module.prod_v3_eks.cluster_name
    endpoint                = module.prod_v3_eks.cluster_endpoint
    node_subnet_ids         = module.prod_v3_network.node_subnet_ids
    pod_subnet_ids          = module.prod_v3_network.pod_subnet_ids
    api_access_instance_id  = one(data.aws_instances.prod_v3_api_access.ids)
    port_forward_document   = module.prod_v3_eks.api_port_forward_document_name
    control_plane_log_group = module.prod_v3_eks.control_plane_log_group_name
  }
}
