# ---------------------------------------------------------------
# V3 prod System Add-ons
# - EKS Cluster 운영에 필요한 AWS 관리형 Add-on을 구성한다.
# - Cilium은 별도 Helm 구성으로 관리하므로 이 모듈에서 변경하지 않는다.
# ---------------------------------------------------------------
locals {
  common_tags = {
    Environment = "prod"
    Version     = "v3"
  }
}

resource "aws_eks_addon" "coredns" {
  cluster_name  = var.cluster_name
  addon_name    = "coredns"
  addon_version = var.coredns_addon_version

  # Git에 선언된 설정을 기준으로 Add-on 설정 충돌을 해소한다.
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  configuration_values = jsonencode({
    replicaCount = 2

    # CoreDNS는 Karpenter가 공급할 Application Node가 아닌
    # 항상 유지되는 System Managed Node Group에서 실행한다.
    nodeSelector = {
      "lookddak.io/node-pool" = "system"
    }
  })

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-coredns"
  })
}

resource "aws_eks_addon" "ebs_csi_driver" {
  cluster_name             = var.cluster_name
  addon_name               = "aws-ebs-csi-driver"
  addon_version            = var.ebs_csi_driver_addon_version
  service_account_role_arn = var.ebs_csi_driver_role_arn

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  configuration_values = jsonencode({
    controller = {
      nodeSelector = {
        "lookddak.io/node-pool" = "system"
      }
    }
  })

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-aws-ebs-csi-driver"
  })
}

