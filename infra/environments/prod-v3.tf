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

module "prod_v3_system_node_group" {
  source = "./prod/v3/system-node-group"

  cluster_name    = module.prod_v3_eks.cluster_name
  cluster_version = module.prod_v3_eks.cluster_version
  subnet_ids      = module.prod_v3_network.node_subnet_ids
}

module "prod_v3_controller_iam" {
  source = "./prod/v3/iam"

  cluster_name      = module.prod_v3_eks.cluster_name
  oidc_provider_arn = module.prod_v3_eks.oidc_provider_arn
  oidc_issuer       = module.prod_v3_eks.oidc_issuer
  route53_zone_id   = module.shared_core.route53_zone_id
}

module "prod_v3_karpenter_iam" {
  source = "./prod/v3/karpenter-iam"

  cluster_name      = module.prod_v3_eks.cluster_name
  oidc_provider_arn = module.prod_v3_eks.oidc_provider_arn
  oidc_issuer       = module.prod_v3_eks.oidc_issuer
}

module "prod_v3_system_addons" {
  source = "./prod/v3/system-addons"

  cluster_name = module.prod_v3_eks.cluster_name

  ebs_csi_driver_role_arn = module.prod_v3_controller_iam.ebs_csi_driver_role_arn

  # CoreDNS를 배치할 On-Demand System Node Group을 먼저 구성한다.
  depends_on = [module.prod_v3_system_node_group]
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

output "prod_v3_system_node_group" {
  description = "Prod V3 On-Demand System Managed Node Group 정보"
  value = {
    name               = module.prod_v3_system_node_group.node_group_name
    role_arn           = module.prod_v3_system_node_group.node_role_arn
    launch_template_id = module.prod_v3_system_node_group.launch_template_id
    coredns_version    = module.prod_v3_system_addons.coredns_addon_version
    ebs_csi_version    = module.prod_v3_system_addons.ebs_csi_driver_addon_version
  }
}

output "prod_v3_controller_role_arns" {
  description = "Prod GitOps ServiceAccount에 연결할 Controller IRSA Role ARN"
  value = {
    cilium_operator              = module.prod_v3_controller_iam.cilium_operator_role_arn
    aws_load_balancer_controller = module.prod_v3_controller_iam.aws_load_balancer_controller_role_arn
    cert_manager                 = module.prod_v3_controller_iam.cert_manager_role_arn
    ebs_csi_driver               = module.prod_v3_controller_iam.ebs_csi_driver_role_arn
    karpenter_controller         = module.prod_v3_karpenter_iam.controller_role_arn
  }
}

output "prod_v3_karpenter_node" {
  description = "Prod Karpenter EC2NodeClass에 넣을 Node IAM 정보"
  value = {
    role_arn              = module.prod_v3_karpenter_iam.node_role_arn
    instance_profile_name = module.prod_v3_karpenter_iam.node_instance_profile_name
  }
}
