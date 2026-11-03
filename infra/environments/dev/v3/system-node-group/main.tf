# ---------------------------------------------------------------
# V3 dev System Managed Node Group
# - Cilium, CoreDNS, Karpenter, Argo CD 등 클러스터 핵심 구성요소를 실행한다.
# - 애플리케이션 Node는 이후 Karpenter가 별도로 공급한다.
# - 초기 부트스트랩 단계에서는 일반 Pod 차단 Taint를 적용하지 않는다.
# ---------------------------------------------------------------
locals {
  common_tags = {
    Environment = "dev"
    Version     = "v3"
    NodePool    = "system"
  }

  node_role_policy_arns = toset([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPullOnly",
  ])
}

data "aws_iam_policy_document" "node_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "system_node" {
  name               = "${var.cluster_name}-system-node-role"
  assume_role_policy = data.aws_iam_policy_document.node_assume.json

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "system_node" {
  for_each = local.node_role_policy_arns

  role       = aws_iam_role.system_node.name
  policy_arn = each.value
}

# MNG에 Custom Launch Template을 처음부터 연결해 두면 같은 Template의
# 새 버전으로 디스크·Metadata 설정을 안전하게 갱신할 수 있다.
# Subnet, IAM Instance Profile, Security Group, Instance Type과 AMI는
# Launch Template이 아니라 aws_eks_node_group에서 관리한다.
resource "aws_launch_template" "system" {
  name_prefix            = "${var.cluster_name}-system-"
  update_default_version = true

  metadata_options {
    http_endpoint               = "enabled"
    http_protocol_ipv6          = "disabled"
    http_put_response_hop_limit = 2
    http_tokens                 = "required"
    instance_metadata_tags      = "disabled"
  }

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      delete_on_termination = true
      encrypted             = true
      volume_size           = 30
      volume_type           = "gp3"
    }
  }

  tag_specifications {
    resource_type = "instance"

    tags = merge(local.common_tags, {
      Name = "${var.cluster_name}-system"
    })
  }

  tag_specifications {
    resource_type = "volume"

    tags = merge(local.common_tags, {
      Name = "${var.cluster_name}-system"
    })
  }

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-system"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_eks_node_group" "system" {
  cluster_name    = var.cluster_name
  node_group_name = "${var.cluster_name}-system"
  node_role_arn   = aws_iam_role.system_node.arn
  subnet_ids      = var.subnet_ids
  version         = var.cluster_version

  ami_type       = "AL2023_x86_64_STANDARD"
  capacity_type  = "ON_DEMAND"
  instance_types = ["m7i.large", "m6i.large"]

  scaling_config {
    min_size     = 2
    desired_size = 2
    max_size     = 3
  }

  update_config {
    max_unavailable = 1
  }

  labels = {
    "lookddak.io/node-pool" = "system"
  }

  launch_template {
    id      = aws_launch_template.system.id
    version = aws_launch_template.system.latest_version
  }

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-system"
  })

  depends_on = [aws_iam_role_policy_attachment.system_node]
}
