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
  alert_queue_arn   = module.prod_v1_monitoring.alert_queue_arn
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

module "prod_v3_database_access" {
  source = "./prod/v3/database-access"

  eks_cluster_security_group_id = module.prod_v3_eks.cluster_security_group_id

  mysql_security_group_id = module.prod_v2_network.security_group_ids["mysql"]
  mysql_endpoint          = module.prod_v2_database.mysql_address

  postgresql_security_group_id = module.prod_v2_network.security_group_ids["postgresql"]
  postgresql_endpoint          = module.prod_v2_database.rds_address
  postgresql_port              = module.prod_v2_database.rds_port

  db_access_instance_id        = module.prod_v2_monitoring.instance_id
  db_access_instance_role_name = module.prod_v2_monitoring.instance_role_name
}

module "prod_v3_workload_iam" {
  source = "./prod/v3/workload-iam"

  name_prefix       = "lookddak-prod-v3"
  oidc_provider_arn = module.prod_v3_eks.oidc_provider_arn
  oidc_issuer       = module.prod_v3_eks.oidc_issuer

  images_bucket_name = module.prod_s3.images_bucket_name
  sqs_queue_arns     = module.prod_v2_sqs.queue_arns
  sqs_queue_urls     = module.prod_v2_sqs.queue_urls
}

module "prod_v3_monitoring_node_group" {
  source = "./prod/v3/monitoring-node-group"

  cluster_name    = module.prod_v3_eks.cluster_name
  cluster_version = module.prod_v3_eks.cluster_version
  subnet_id       = module.prod_v3_network.node_subnet_ids[0]
}

module "prod_v3_monitoring" {
  source = "./prod/v3/monitoring"

  name_prefix         = "lookddak-prod-v3"
  oidc_provider_arn   = module.prod_v3_eks.oidc_provider_arn
  oidc_issuer         = module.prod_v3_eks.oidc_issuer
  db_log_instance_ids = ["lookddak-prod-v2-mysql", "lookddak-prod-v2-postgresql"]

  mysql_endpoint               = module.prod_v2_database.mysql_address
  db_access_instance_id        = module.prod_v2_monitoring.instance_id
  db_access_instance_role_name = module.prod_v2_monitoring.instance_role_name

  grafana_user_pool_id = module.prod_v2_monitoring.grafana_user_pool_id
  grafana_domain_name  = "grafana.v3-prod.lookddak.com"
}

module "prod_v3_argocd_edge" {
  source = "./prod/v3/edge"

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }

  cluster_name    = module.prod_v3_eks.cluster_name
  vpc_id          = data.aws_vpc.prod_v3.id
  route53_zone_id = module.shared_core.route53_zone_id
  domain_name     = "argocd.lookddak.com"
  additional_domain_names = [
    "lookddak.com",
    "www.lookddak.com",
    "v3-prod.lookddak.com",
    "grafana.v3-prod.lookddak.com",
  ]

  # 동일 계정에서 같은 도메인의 ACM DNS 검증 CNAME은 재사용된다.
  # 기존 V2 인증서가 관리하는 레코드를 사용해 중복 Route 53 리소스를 만들지 않는다.
  prevalidated_domain_names = [
    "lookddak.com",
    "www.lookddak.com",
  ]

  # CloudFront는 같은 Alias를 두 Distribution에 동시에 연결할 수 없다.
  # V2 Distribution의 Alias 해제가 끝난 뒤 V3 Distribution을 갱신한다.
  cutover_after_distribution_id = module.prod_v2_edge.cloudfront_distribution_id
}

output "prod_v3_cluster" {
  description = "Prod V3 EKS Control Plane 접속 정보"
  value = {
    name                    = module.prod_v3_eks.cluster_name
    endpoint                = module.prod_v3_eks.cluster_endpoint
    node_subnet_ids         = module.prod_v3_network.node_subnet_ids
    pod_subnet_ids          = module.prod_v3_network.pod_subnet_ids
    api_access_instance_id  = module.prod_v2_monitoring.instance_id
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
    argocd_notifications         = module.prod_v3_controller_iam.argocd_notifications_role_arn
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

output "prod_v3_database_parameter_names" {
  description = "Prod V3 Parameter Store paths for the shared Prod databases"
  value       = module.prod_v3_database_access.parameter_names
}

output "prod_v3_database_bootstrap_command" {
  description = "Command that creates or verifies Prod V3 users on the shared Prod databases"
  value       = module.prod_v3_database_access.bootstrap_command
}

output "prod_v3_workload_role_arns" {
  description = "Prod GitOps ServiceAccount에 연결할 워크로드별 IRSA Role ARN"
  value       = module.prod_v3_workload_iam.role_arns
}

output "prod_v3_runtime_parameter_names" {
  description = "기존 Prod Queue·S3를 가리키는 V3 전용 Parameter Store 경로"
  value       = module.prod_v3_workload_iam.runtime_parameter_names
}

output "prod_v3_idm_vton_modal_parameter_names" {
  description = "실제 Modal SDK Token을 수동 입력할 Prod SecureString 경로"
  value       = module.prod_v3_workload_iam.idm_vton_modal_parameter_names
}

output "prod_v3_argocd_edge" {
  description = "Prod V3 CloudFront·Route 53 연결 정보"
  value = {
    url                        = module.prod_v3_argocd_edge.argocd_url
    validation_url             = module.prod_v3_argocd_edge.validation_urls["v3-prod.lookddak.com"]
    cloudfront_distribution_id = module.prod_v3_argocd_edge.cloudfront_distribution_id
    cloudfront_domain_name     = module.prod_v3_argocd_edge.cloudfront_domain_name
    gateway_nlb_dns_name       = module.prod_v3_argocd_edge.gateway_nlb_dns_name
    gateway_nlb_security_group = module.prod_v3_argocd_edge.gateway_nlb_security_group_id
    web_acl_arn                = module.prod_v3_argocd_edge.web_acl_arn
  }
}

output "prod_v3_monitoring_bucket_names" {
  description = "Prod V3 Loki·Tempo Helm values에 넣을 S3 버킷 이름"
  value       = module.prod_v3_monitoring.bucket_names
}

output "prod_v3_monitoring_role_arns" {
  description = "Prod V3 monitoring Namespace ServiceAccount에 연결할 IRSA Role ARN"
  value       = module.prod_v3_monitoring.role_arns
}

output "prod_v3_mysql_exporter_bootstrap_command" {
  description = "Prod V3 MySQL exporter 계정을 최초 1회 구성하는 명령"
  value       = module.prod_v3_monitoring.mysql_exporter_bootstrap_command
}

output "prod_v3_grafana_cognito_client_id" {
  description = "Prod V3 oauth2-proxy에 넣을 Grafana Cognito App Client ID"
  value       = module.prod_v3_monitoring.grafana_cognito_client_id
}

output "prod_v3_grafana_cognito_user_pool_id" {
  description = "Prod V3 oauth2-proxy OIDC issuer에 넣을 Cognito 사용자 풀 ID (Prod V2 Grafana 사용자 풀)"
  value       = module.prod_v2_monitoring.grafana_user_pool_id
}

output "prod_v3_redis_readonly_acl_rule" {
  description = "Prod V3 Redis ACL user 규칙 (GitOps redis-cache-config에 넣는다)"
  value       = module.prod_v3_monitoring.redis_readonly_acl_rule
}

