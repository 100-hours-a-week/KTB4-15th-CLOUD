# ---------------------------------------------------------------
# V3 dev → 기존 Dev V2 PostgreSQL 접근
# - price-crawler, chat-ai, vton-orchestrator가 V2 PostgreSQL(app DB)을 계속 사용한다
# - Karpenter Application Node와 Cilium Pod ENI가 쓰는 EKS Cluster SG에서만 5432 허용 (MySQL과 같은 방식)
# - Pod 단위 제한은 GITOPS CiliumNetworkPolicy egress로 한다 (Pod가 노드 SG를 공유하므로)
# ---------------------------------------------------------------
locals {
  common_tags = {
    Component   = "postgresql-access"
    Environment = "dev"
    Version     = "v3"
  }
}

resource "aws_vpc_security_group_ingress_rule" "postgresql_from_v3_eks" {
  security_group_id            = var.postgresql_security_group_id
  description                  = "PostgreSQL traffic from V3 EKS application workloads"
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = var.eks_cluster_security_group_id

  tags = local.common_tags
}
