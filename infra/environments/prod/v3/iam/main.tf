# ---------------------------------------------------------------
# V3 prod Controller IRSA Role
# - Pod(ServiceAccount) 단위로 AWS 권한을 준다. 노드 Role에는 앱/애드온 권한을 넣지 않는다.
# - 신뢰 정책은 OIDC aud(sts.amazonaws.com) + sub(namespace:serviceaccount)로 한 SA만 허용한다.
# ---------------------------------------------------------------
locals {
  common_tags = {
    Environment = "prod"
    Version     = "v3"
  }

  irsa = {
    cilium_operator = {
      role_name       = "${var.cluster_name}-cilium-operator"
      namespace       = "kube-system"
      service_account = "cilium-operator"
    }
    aws_load_balancer_controller = {
      role_name       = "${var.cluster_name}-aws-load-balancer-controller"
      namespace       = "kube-system"
      service_account = "aws-load-balancer-controller"
    }
    cert_manager = {
      role_name       = "${var.cluster_name}-cert-manager"
      namespace       = "kube-system"
      service_account = "cert-manager"
    }
    ebs_csi_driver = {
      role_name       = "${var.cluster_name}-ebs-csi-driver"
      namespace       = "kube-system"
      service_account = "ebs-csi-controller-sa"
    }
  }
}

data "aws_iam_policy_document" "irsa_assume" {
  for_each = local.irsa

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_issuer}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_issuer}:sub"
      values   = ["system:serviceaccount:${each.value.namespace}:${each.value.service_account}"]
    }
  }
}

resource "aws_iam_role" "irsa" {
  for_each = local.irsa

  name               = each.value.role_name
  assume_role_policy = data.aws_iam_policy_document.irsa_assume[each.key].json

  tags = merge(local.common_tags, {
    ServiceAccount = "${each.value.namespace}/${each.value.service_account}"
  })
}
