locals {
  name = "${var.cluster_name}-monitoring"

  common_tags = {
    Environment = "dev"
    Version     = "v3"
    NodePool    = "monitoring"
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

resource "aws_iam_role" "monitoring_node" {
  name               = "${local.name}-node-role"
  assume_role_policy = data.aws_iam_policy_document.node_assume.json

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "monitoring_node" {
  for_each = local.node_role_policy_arns

  role       = aws_iam_role.monitoring_node.name
  policy_arn = each.value
}

resource "aws_launch_template" "monitoring" {
  name_prefix            = "${local.name}-"
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
      Name = local.name
    })
  }

  tag_specifications {
    resource_type = "volume"

    tags = merge(local.common_tags, {
      Name = local.name
    })
  }

  tags = merge(local.common_tags, {
    Name = local.name
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_eks_node_group" "monitoring" {
  cluster_name    = var.cluster_name
  node_group_name = local.name
  node_role_arn   = aws_iam_role.monitoring_node.arn
  subnet_ids      = [var.subnet_id]
  version         = var.cluster_version

  ami_type       = "AL2023_ARM_64_STANDARD"
  capacity_type  = "ON_DEMAND"
  instance_types = var.instance_types

  scaling_config {
    min_size     = 1
    desired_size = 1
    max_size     = 2
  }

  update_config {
    max_unavailable = 1
  }

  labels = {
    "lookddak.io/node-pool" = "monitoring"
  }

  taint {
    key    = "dedicated"
    value  = "monitoring"
    effect = "NO_SCHEDULE"
  }

  launch_template {
    id      = aws_launch_template.monitoring.id
    version = aws_launch_template.monitoring.latest_version
  }

  tags = merge(local.common_tags, {
    Name = local.name
  })

  depends_on = [aws_iam_role_policy_attachment.monitoring_node]
}
