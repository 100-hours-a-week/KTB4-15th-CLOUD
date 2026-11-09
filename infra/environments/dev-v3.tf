# ---------------------------------------------------------------
# V3 dev (EKS)
# - 기존 dev VPC를 쓰고, 새 리소스는 dev/v3에만 둔다 (V1/V2 파일과 충돌 방지).
# ---------------------------------------------------------------
locals {
  dev_v3_cluster_name = "lookddak-dev"
}

module "dev_v3_sqs" {
  source = "./dev/v3/sqs"
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

  # private 엔드포인트 접근: 기존 dev bastion(SSM)
  bastion_security_group_id = module.dev_v2_db_access.security_group_id
}

module "dev_v3_mysql" {
  source = "./dev/v3/mysql"

  mysql_endpoint                = module.dev_v2_database.mysql_address
  mysql_security_group_id       = module.dev_v2_network.security_group_ids["mysql"]
  eks_cluster_security_group_id = module.dev_v3_eks.cluster_security_group_id
  db_access_instance_id         = module.dev_v2_db_access.instance_id
  db_access_instance_role_name  = module.dev_v2_db_access.instance_role_name
}

module "dev_v3_iam" {
  source = "./dev/v3/iam"

  cluster_name      = local.dev_v3_cluster_name
  oidc_provider_arn = module.dev_v3_eks.oidc_provider_arn
  oidc_issuer       = module.dev_v3_eks.oidc_issuer
  route53_zone_id   = module.shared_core.route53_zone_id
  alert_queue_arn   = module.prod_v1_monitoring.alert_queue_arn
}

module "dev_v3_postgresql_access" {
  source = "./dev/v3/postgresql-access"

  postgresql_security_group_id  = module.dev_v2_network.security_group_ids["postgresql"]
  eks_cluster_security_group_id = module.dev_v3_eks.cluster_security_group_id
}

module "dev_v3_postgresql" {
  source = "./dev/v3/postgresql"

  postgresql_endpoint          = module.dev_v2_database.rds_address
  postgresql_port              = module.dev_v2_database.rds_port
  db_access_instance_id        = module.dev_v2_db_access.instance_id
  db_access_instance_role_name = module.dev_v2_db_access.instance_role_name
}

module "dev_v3_workload_iam" {
  source = "./dev/v3/workload-iam"

  name_prefix        = "lookddak-dev-v3"
  oidc_provider_arn  = module.dev_v3_eks.oidc_provider_arn
  oidc_issuer        = module.dev_v3_eks.oidc_issuer
  images_bucket_name = module.dev_s3.images_bucket_name
  sqs_queue_arns     = module.dev_v3_sqs.queue_arns
}

module "dev_v3_karpenter_iam" {
  source = "./dev/v3/karpenter-iam"

  cluster_name      = module.dev_v3_eks.cluster_name
  oidc_provider_arn = module.dev_v3_eks.oidc_provider_arn
  oidc_issuer       = module.dev_v3_eks.oidc_issuer
}

module "dev_v3_system_node_group" {
  source = "./dev/v3/system-node-group"

  cluster_name    = module.dev_v3_eks.cluster_name
  cluster_version = module.dev_v3_eks.cluster_version
  subnet_ids      = module.dev_v3_network.node_subnet_ids
}

module "dev_v3_system_addons" {
  source = "./dev/v3/system-addons"

  cluster_name = module.dev_v3_eks.cluster_name

  ebs_csi_driver_role_arn = module.dev_v3_iam.ebs_csi_driver_role_arn

  # CoreDNS Pod를 배치할 System Node가 먼저 준비되어야 한다.
  depends_on = [module.dev_v3_system_node_group]
}

module "dev_v3_monitoring_node_group" {
  source = "./dev/v3/monitoring-node-group"

  cluster_name    = module.dev_v3_eks.cluster_name
  cluster_version = module.dev_v3_eks.cluster_version
  subnet_id       = module.dev_v3_network.node_subnet_ids[0]
}

module "dev_v3_monitoring" {
  source = "./dev/v3/monitoring"

  name_prefix         = "lookddak-dev-v3"
  oidc_provider_arn   = module.dev_v3_eks.oidc_provider_arn
  oidc_issuer         = module.dev_v3_eks.oidc_issuer
  db_log_instance_ids = ["lookddak-dev-v2-mysql", "lookddak-dev-postgresql"]

  mysql_endpoint               = module.dev_v2_database.mysql_address
  db_access_instance_id        = module.dev_v2_db_access.instance_id
  db_access_instance_role_name = module.dev_v2_db_access.instance_role_name
}

# CloudFront → VPC Origin → 내부 NLB(Istio Gateway). NLB는 GITOPS(AWS LB Controller)가 만든다
module "dev_v3_edge" {
  source = "./dev/v3/edge"

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }

  cluster_name    = module.dev_v3_eks.cluster_name
  vpc_id          = module.dev_v1_network.vpc_id
  route53_zone_id = module.shared_core.route53_zone_id

  # v3-dev.lookddak.com으로 V3 애플리케이션 경로를 먼저 검증한다.
  # dev.lookddak.com은 V2 → V3 전환 때, grafana.dev는 V2 Grafana CloudFront 정리 후 추가한다.
  domain_names = ["argocd.dev.lookddak.com", "v3-dev.lookddak.com"]
}

output "dev_v3_sqs_queue_urls" {
  description = "V3 Dev 피팅 Main Queue URL"
  value       = module.dev_v3_sqs.queue_urls
}

output "dev_v3_sqs_queue_arns" {
  description = "V3 Dev 피팅 Main Queue ARN"
  value       = module.dev_v3_sqs.queue_arns
}

output "dev_v3_sqs_dlq_urls" {
  description = "V3 Dev 피팅 DLQ URL"
  value       = module.dev_v3_sqs.dlq_urls
}

output "dev_v3_sqs_dlq_arns" {
  description = "V3 Dev 피팅 DLQ ARN"
  value       = module.dev_v3_sqs.dlq_arns
}

output "dev_v3_workload_role_arns" {
  description = "GitOps ServiceAccount에 연결할 V3 Dev 워크로드별 IRSA Role ARN"
  value       = module.dev_v3_workload_iam.role_arns
}

output "dev_v3_workload_role_names" {
  description = "V3 Dev 워크로드별 IRSA Role 이름"
  value       = module.dev_v3_workload_iam.role_names
}

output "dev_v3_argocd_notifications_role_arn" {
  description = "GitOps Argo CD Notifications Controller에 연결할 V3 Dev IRSA Role ARN"
  value       = module.dev_v3_iam.argocd_notifications_role_arn
}

output "dev_v3_mysql_database_name" {
  description = "기존 Dev MySQL RDS 안에 격리한 V3 Database 이름"
  value       = module.dev_v3_mysql.database_name
}

output "dev_v3_mysql_parameter_names" {
  description = "V3 Spring 워크로드가 사용할 MySQL Parameter Store 경로"
  value       = module.dev_v3_mysql.parameter_names
}

output "dev_v3_mysql_bootstrap_command" {
  description = "V3 Database와 전용 사용자를 최초 1회 구성하는 SSM Run Command"
  value       = module.dev_v3_mysql.bootstrap_command
}

output "dev_v3_postgresql_database_name" {
  description = "기존 Dev PostgreSQL RDS 안에 격리한 V3 Database 이름"
  value       = module.dev_v3_postgresql.database_name
}

output "dev_v3_postgresql_parameter_names" {
  description = "V3 AI·Crawler 워크로드가 사용할 PostgreSQL Parameter Store 경로"
  value       = module.dev_v3_postgresql.parameter_names
}

output "dev_v3_postgresql_bootstrap_command" {
  description = "V3 PostgreSQL Database와 전용 사용자를 최초 1회 구성하는 SSM Run Command"
  value       = module.dev_v3_postgresql.bootstrap_command
}

output "dev_v3_monitoring_bucket_names" {
  description = "Loki·Tempo Helm values에 넣을 S3 버킷 이름"
  value       = module.dev_v3_monitoring.bucket_names
}

output "dev_v3_monitoring_role_arns" {
  description = "monitoring Namespace ServiceAccount에 연결할 IRSA Role ARN"
  value       = module.dev_v3_monitoring.role_arns
}

output "dev_v3_db_log_tailer_repository_url" {
  description = "db-log-tailer 이미지 저장소 URL"
  value       = module.dev_v3_monitoring.db_log_tailer_repository_url
}

output "dev_v3_ebs_csi_driver_role_arn" {
  description = "kube-system/ebs-csi-controller-sa IRSA Role ARN"
  value       = module.dev_v3_iam.ebs_csi_driver_role_arn
}

output "dev_v3_mysql_exporter_bootstrap_command" {
  description = "V3 MySQL exporter 계정을 최초 1회 구성하는 SSM Run Command"
  value       = module.dev_v3_monitoring.mysql_exporter_bootstrap_command
}
