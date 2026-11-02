# ---------------------------------------------------------------
# Cilium Operator (ENI IPAM)
# - Operator가 노드에 Pod용 ENI를 만들고 붙이고, IP/Prefix(/28)를 할당한다.
# - 권한 목록: Cilium 1.20 ENI IPAM 문서 기준
#   DescribeTags: ENI GC 기본값, UnassignPrivateIpAddresses/UnassignENIPrefixes: 남는 IP 반납
# - Describe/Create/Attach는 리소스 단위 제한이 어려워 "*"로 둔다 (dev).
#   태그 생성은 ENI에만 허용한다.
# ---------------------------------------------------------------
data "aws_iam_policy_document" "cilium_operator" {
  statement {
    sid = "Describe"
    actions = [
      "ec2:DescribeInstances",
      "ec2:DescribeInstanceTypes",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DescribeRouteTables",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeSubnets",
      "ec2:DescribeTags",
      "ec2:DescribeVpcs",
    ]
    resources = ["*"]
  }

  statement {
    sid = "ManageEni"
    actions = [
      "ec2:AssignPrivateIpAddresses",
      "ec2:AttachNetworkInterface",
      "ec2:CreateNetworkInterface",
      "ec2:DeleteNetworkInterface",
      "ec2:ModifyNetworkInterfaceAttribute",
      "ec2:UnassignPrivateIpAddresses",
      "ec2:UnassignENIPrefixes",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "TagEni"
    actions   = ["ec2:CreateTags"]
    resources = ["arn:aws:ec2:*:*:network-interface/*"]
  }
}

resource "aws_iam_role_policy" "cilium_operator" {
  name   = "cilium-operator-eni"
  role   = aws_iam_role.irsa["cilium_operator"].id
  policy = data.aws_iam_policy_document.cilium_operator.json
}
