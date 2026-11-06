# 각 Role은 V3 EKS의 정확한 Namespace와 ServiceAccount 하나만 신뢰한다.
data "aws_iam_policy_document" "assume" {
  for_each = local.workloads

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

resource "aws_iam_role" "workload" {
  for_each = local.workloads

  name               = "${var.name_prefix}-${each.key}"
  assume_role_policy = data.aws_iam_policy_document.assume[each.key].json

  tags = merge(local.common_tags, {
    Name           = "${var.name_prefix}-${each.key}"
    Workload       = each.key
    ServiceAccount = "${each.value.namespace}/${each.value.service_account}"
  })
}

# ASCP가 각 워크로드에 선언된 Parameter만 파일로 마운트할 수 있게 제한한다.
data "aws_iam_policy_document" "parameters" {
  for_each = local.workloads

  statement {
    sid       = "ReadWorkloadParameters"
    actions   = ["ssm:GetParameters"]
    resources = [for name in each.value.parameter_names : "${local.ssm_parameter_arn_prefix}${name}"]
  }

  statement {
    sid       = "DescribeParameters"
    actions   = ["ssm:DescribeParameters"]
    resources = ["*"]
  }

  statement {
    sid       = "DecryptParametersViaSsm"
    actions   = ["kms:Decrypt"]
    resources = [data.aws_kms_alias.ssm.target_key_arn]

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["ssm.${local.region}.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "parameters" {
  for_each = local.workloads

  name   = "${var.name_prefix}-${each.key}-parameters"
  role   = aws_iam_role.workload[each.key].id
  policy = data.aws_iam_policy_document.parameters[each.key].json
}
