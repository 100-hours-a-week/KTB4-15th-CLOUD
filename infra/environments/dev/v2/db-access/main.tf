data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

data "aws_region" "current" {}

data "aws_vpc" "dev" {
  id = var.vpc_id
}

data "aws_ssm_parameter" "al2023_arm64" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
}

locals {
  name = "lookddak-dev-db-access"

  common_tags = {
    Component   = "db-access"
    Environment = "dev"
    Purpose     = "ssm-db-query-tunnel"
    Version     = "v2"
  }
}

# ---------------------------------------------------------------
# Network
# - No inbound rules are required for Session Manager.
# - Outbound is limited to the two Dev RDS engines, VPC DNS, and HTTPS
#   through the existing NAT Gateway for Systems Manager connectivity.
# ---------------------------------------------------------------
resource "aws_security_group" "this" {
  name                   = "${local.name}-sg"
  description            = "SSM port-forwarding access to LookDDak dev databases"
  vpc_id                 = var.vpc_id
  revoke_rules_on_delete = true

  tags = merge(local.common_tags, {
    Name = "${local.name}-sg"
  })
}

resource "aws_vpc_security_group_egress_rule" "mysql" {
  security_group_id            = aws_security_group.this.id
  description                  = "MySQL tunnel traffic to Dev V2 RDS"
  ip_protocol                  = "tcp"
  from_port                    = 3306
  to_port                      = 3306
  referenced_security_group_id = var.mysql_security_group_id
}

resource "aws_vpc_security_group_egress_rule" "postgresql" {
  security_group_id            = aws_security_group.this.id
  description                  = "PostgreSQL tunnel traffic to Dev V2 RDS"
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = var.postgresql_security_group_id
}

resource "aws_vpc_security_group_egress_rule" "https" {
  security_group_id = aws_security_group.this.id
  description       = "HTTPS to Systems Manager through the existing NAT Gateway"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "dns_udp" {
  security_group_id = aws_security_group.this.id
  description       = "DNS resolution in the Dev VPC"
  ip_protocol       = "udp"
  from_port         = 53
  to_port           = 53
  cidr_ipv4         = data.aws_vpc.dev.cidr_block
}

resource "aws_vpc_security_group_egress_rule" "dns_tcp" {
  security_group_id = aws_security_group.this.id
  description       = "DNS resolution fallback in the Dev VPC"
  ip_protocol       = "tcp"
  from_port         = 53
  to_port           = 53
  cidr_ipv4         = data.aws_vpc.dev.cidr_block
}

resource "aws_vpc_security_group_ingress_rule" "mysql_from_access_node" {
  security_group_id            = var.mysql_security_group_id
  description                  = "MySQL queries from the SSM DB access node"
  ip_protocol                  = "tcp"
  from_port                    = 3306
  to_port                      = 3306
  referenced_security_group_id = aws_security_group.this.id
}

resource "aws_vpc_security_group_ingress_rule" "postgresql_from_access_node" {
  security_group_id            = var.postgresql_security_group_id
  description                  = "PostgreSQL queries from the SSM DB access node"
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = aws_security_group.this.id
}

# ---------------------------------------------------------------
# EC2 instance role
# ---------------------------------------------------------------
resource "aws_iam_role" "instance" {
  name        = "${local.name}-instance-role"
  description = "Systems Manager role for the LookDDak dev DB access node"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "this" {
  name = "${local.name}-instance-profile"
  role = aws_iam_role.instance.name

  tags = local.common_tags
}

# ---------------------------------------------------------------
# Private SSM access node
# ---------------------------------------------------------------
resource "aws_instance" "this" {
  ami                         = data.aws_ssm_parameter.al2023_arm64.value
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [aws_security_group.this.id]
  iam_instance_profile        = aws_iam_instance_profile.this.name
  associate_public_ip_address = false
  key_name                    = null

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 8
    encrypted             = true
    delete_on_termination = true
  }

  user_data = <<-EOF
    #!/bin/bash
    systemctl enable --now amazon-ssm-agent
  EOF

  tags = merge(local.common_tags, {
    Name = local.name
  })

  # 최신 AL2023 AMI가 나올 때마다 인스턴스가 교체되지 않게 한다.
  # AMI 갱신이 필요하면 이 줄을 잠시 빼거나 -replace로 교체한다.
  lifecycle {
    ignore_changes = [ami]
  }

  depends_on = [aws_iam_role_policy_attachment.ssm_core]
}

# ---------------------------------------------------------------
# Fixed-destination Session Manager documents
# - Team members can select only the local listener port.
# - Remote hosts and ports cannot be overridden.
# ---------------------------------------------------------------
resource "aws_ssm_document" "mysql_port_forward" {
  name            = "lookddak-dev-mysql-port-forward"
  document_type   = "Session"
  document_format = "JSON"

  content = jsonencode({
    schemaVersion = "1.0"
    description   = "Forward local port 13306 to the LookDDak Dev V2 MySQL RDS endpoint"
    sessionType   = "Port"
    parameters = {
      localPortNumber = {
        type           = "String"
        description    = "Fixed local MySQL listener port"
        default        = "13306"
        allowedPattern = "^13306$"
      }
    }
    properties = {
      type            = "LocalPortForwarding"
      host            = var.mysql_endpoint
      portNumber      = "3306"
      localPortNumber = "{{ localPortNumber }}"
    }
  })

  tags = merge(local.common_tags, {
    Database = "mysql"
  })
}

resource "aws_ssm_document" "postgresql_port_forward" {
  name            = "lookddak-dev-postgresql-port-forward"
  document_type   = "Session"
  document_format = "JSON"

  content = jsonencode({
    schemaVersion = "1.0"
    description   = "Forward local port 15432 to the LookDDak Dev V2 PostgreSQL RDS endpoint"
    sessionType   = "Port"
    parameters = {
      localPortNumber = {
        type           = "String"
        description    = "Fixed local PostgreSQL listener port"
        default        = "15432"
        allowedPattern = "^15432$"
      }
    }
    properties = {
      type            = "LocalPortForwarding"
      host            = var.postgresql_endpoint
      portNumber      = "5432"
      localPortNumber = "{{ localPortNumber }}"
    }
  })

  tags = merge(local.common_tags, {
    Database = "postgresql"
  })
}

# ---------------------------------------------------------------
# Existing shared MQ test user: port-forwarding sessions only
# - No RunShell document, SendCommand, EC2 mutation, or RDS mutation.
# ---------------------------------------------------------------
resource "aws_iam_policy" "tunnel_user" {
  name        = "lookddak-dev-db-tunnel-access"
  description = "Open fixed MySQL and PostgreSQL SSM tunnels through the Dev DB access node"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "StartFixedDatabaseTunnels"
      Effect = "Allow"
      Action = "ssm:StartSession"
      Resource = [
        aws_instance.this.arn,
        aws_ssm_document.mysql_port_forward.arn,
        aws_ssm_document.postgresql_port_forward.arn,
      ]
      }, {
      Sid      = "OpenOwnSessionDataChannel"
      Effect   = "Allow"
      Action   = "ssmmessages:OpenDataChannel"
      Resource = "arn:${data.aws_partition.current.partition}:ssm:*:${data.aws_caller_identity.current.account_id}:session/$${aws:userid}-*"
      }, {
      Sid    = "InspectDbAccessNode"
      Effect = "Allow"
      Action = [
        "ec2:DescribeInstances",
        "ssm:DescribeInstanceInformation",
        "ssm:GetConnectionStatus",
      ]
      Resource = "*"
      }, {
      Sid    = "ManageOwnSessions"
      Effect = "Allow"
      Action = [
        "ssm:ResumeSession",
        "ssm:TerminateSession",
      ]
      Resource = "arn:${data.aws_partition.current.partition}:ssm:*:${data.aws_caller_identity.current.account_id}:session/$${aws:userid}-*"
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_user_policy_attachment" "tunnel_user" {
  user       = var.tunnel_user_name
  policy_arn = aws_iam_policy.tunnel_user.arn
}

