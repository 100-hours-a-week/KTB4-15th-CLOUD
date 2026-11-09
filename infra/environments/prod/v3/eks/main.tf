# ---------------------------------------------------------------
# V3 prod EKS Control Plane
# - Control Plane만 만든다. 노드 그룹은 Cilium 설치 뒤 별도 단계에서 만든다.
#   (CNI가 없으면 노드가 NotReady라 노드 그룹 생성이 실패할 수 있다)
# - bootstrap_self_managed_addons = false
#   : aws-node(VPC CNI), kube-proxy, CoreDNS를 자동 설치하지 않는다.
#     CNI는 Cilium(ENI 모드, kube-proxy 대체), CoreDNS는 노드 생성 뒤 애드온으로 설치한다.
# - 인증은 Access Entry(API)만 쓴다. aws-auth ConfigMap은 쓰지 않는다.
# ---------------------------------------------------------------
locals {
  common_tags = {
    Environment = "prod"
    Version     = "v3"
  }
}

data "aws_iam_policy_document" "cluster_assume" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cluster" {
  name               = "${var.cluster_name}-cluster-role"
  assume_role_policy = data.aws_iam_policy_document.cluster_assume.json

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "cluster" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_cloudwatch_log_group" "cluster" {
  name              = "/aws/eks/${var.cluster_name}/cluster"
  retention_in_days = var.cluster_log_retention_days

  tags = local.common_tags
}

resource "aws_eks_cluster" "this" {
  name     = var.cluster_name
  version  = var.cluster_version
  role_arn = aws_iam_role.cluster.arn

  bootstrap_self_managed_addons = false
  deletion_protection           = var.deletion_protection

  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = true
  }

  # API 엔드포인트는 private만 연다. 접근은 VPC 안(bastion SSM 포트포워딩)에서만 한다.
  vpc_config {
    subnet_ids              = var.subnet_ids
    endpoint_private_access = true
    endpoint_public_access  = false
  }

  kubernetes_network_config {
    ip_family         = "ipv4"
    service_ipv4_cidr = var.service_ipv4_cidr
  }

  upgrade_policy {
    support_type = "STANDARD"
  }

  enabled_cluster_log_types = var.cluster_log_types

  tags = merge(local.common_tags, {
    Name = var.cluster_name
  })

  depends_on = [
    aws_cloudwatch_log_group.cluster,
    aws_iam_role_policy_attachment.cluster,
  ]
}

# ---------------------------------------------------------------
# OIDC Provider (IRSA)
# - Cilium Operator, Karpenter, AWS LB Controller, External Secrets가
#   ServiceAccount 단위로 IAM Role을 받는다. Role은 prod/v3/iam에서 만든다.
# ---------------------------------------------------------------
resource "aws_iam_openid_connect_provider" "this" {
  url            = aws_eks_cluster.this.identity[0].oidc[0].issuer
  client_id_list = ["sts.amazonaws.com"]

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-oidc"
  })
}

# ---------------------------------------------------------------
# Access Entry
# - 클러스터를 만든 주체(CI apply Role)는 bootstrap 옵션으로 관리자 권한을 받는다.
# - 로컬에서 kubectl/helm을 쓰는 주체는 여기서 관리자 권한을 준다.
# ---------------------------------------------------------------
resource "aws_eks_access_entry" "admin" {
  for_each = toset(var.admin_principal_arns)

  cluster_name  = aws_eks_cluster.this.name
  principal_arn = each.value
  type          = "STANDARD"

  tags = local.common_tags
}

resource "aws_eks_access_policy_association" "admin" {
  for_each = toset(var.admin_principal_arns)

  cluster_name  = aws_eks_cluster.this.name
  principal_arn = each.value
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.admin]
}
