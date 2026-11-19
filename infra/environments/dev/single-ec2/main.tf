data "aws_partition" "current" {}

data "aws_ssm_parameter" "al2023_arm64" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
}

locals {
  name             = "lookddak-dev-single"
  application_path = "/srv/lookddak"

  common_tags = {
    Component   = "single-ec2"
    Environment = "dev"
    Purpose     = "docker-compose-host"
  }
}

# ---------------------------------------------------------------
# Network
# - The single host is intentionally placed in a public subnet.
# - Only HTTP/HTTPS are exposed. Administrative access uses SSM.
# ---------------------------------------------------------------
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.common_tags, {
    Name = "${local.name}-vpc"
  })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.common_tags, {
    Name = "${local.name}-igw"
  })
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = "${local.name}-public-a"
    Tier = "public"
  })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = merge(local.common_tags, {
    Name = "${local.name}-public-rt"
    Tier = "public"
  })
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "instance" {
  name                   = "${local.name}-sg"
  description            = "Public HTTP and HTTPS access to the LookDDak Single Dev host"
  vpc_id                 = aws_vpc.this.id
  revoke_rules_on_delete = true

  tags = merge(local.common_tags, {
    Name = "${local.name}-sg"
  })
}

resource "aws_vpc_security_group_ingress_rule" "http" {
  security_group_id = aws_security_group.instance.id
  description       = "Public HTTP"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_ingress_rule" "https" {
  security_group_id = aws_security_group.instance.id
  description       = "Public HTTPS"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "all_ipv4" {
  security_group_id = aws_security_group.instance.id
  description       = "Package, image, AWS API, and external AI access"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# ---------------------------------------------------------------
# EC2 role
# ---------------------------------------------------------------
resource "aws_iam_role" "instance" {
  name        = "${local.name}-instance-role"
  description = "Systems Manager access for the LookDDak Single Dev host"

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

resource "aws_iam_instance_profile" "instance" {
  name = "${local.name}-instance-profile"
  role = aws_iam_role.instance.name

  tags = local.common_tags
}

# ---------------------------------------------------------------
# Persistent data volume
# ---------------------------------------------------------------
resource "aws_ebs_volume" "data" {
  availability_zone = var.availability_zone
  type              = "gp3"
  size              = var.data_volume_size_gib
  iops              = 3000
  throughput        = 125
  encrypted         = true

  tags = merge(local.common_tags, {
    Name = "${local.name}-data"
  })

  lifecycle {
    prevent_destroy = true
  }
}

# ---------------------------------------------------------------
# ARM64 Docker Compose host
# ---------------------------------------------------------------
resource "aws_instance" "this" {
  ami                         = data.aws_ssm_parameter.al2023_arm64.value
  instance_type               = var.instance_type
  availability_zone           = var.availability_zone
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.instance.id]
  iam_instance_profile        = aws_iam_instance_profile.instance.name
  associate_public_ip_address = true
  key_name                    = null

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size_gib
    encrypted             = true
    delete_on_termination = true
  }

  user_data_replace_on_change = true
  user_data                   = <<-EOF
    #!/bin/bash
    set -euxo pipefail

    systemctl enable --now amazon-ssm-agent
    install -d -m 0755 ${local.application_path}

    cat >/usr/local/sbin/mount-lookddak-data <<'SCRIPT'
    #!/bin/bash
    set -euo pipefail

    DATA_VOLUME_ID="${aws_ebs_volume.data.id}"
    DATA_VOLUME_SERIAL=$(printf '%s' "$DATA_VOLUME_ID" | tr -d '-')
    DEVICE=""

    for _ in $(seq 1 120); do
      DEVICE=$(lsblk -ndo NAME,SERIAL | awk -v serial="$DATA_VOLUME_SERIAL" '$2 == serial { print "/dev/" $1; exit }')
      if [ -n "$DEVICE" ] && [ -b "$DEVICE" ]; then
        break
      fi
      sleep 5
    done

    if [ -z "$DEVICE" ] || [ ! -b "$DEVICE" ]; then
      echo "Data EBS volume was not attached within 10 minutes" >&2
      exit 1
    fi

    if ! blkid "$DEVICE" >/dev/null 2>&1; then
      mkfs.xfs "$DEVICE"
    fi

    UUID=$(blkid -s UUID -o value "$DEVICE")
    grep -q "^UUID=$UUID " /etc/fstab || echo "UUID=$UUID ${local.application_path} xfs defaults,nofail 0 2" >>/etc/fstab
    mountpoint -q ${local.application_path} || mount ${local.application_path}
    chown ec2-user:ec2-user ${local.application_path}
    SCRIPT

    chmod 0755 /usr/local/sbin/mount-lookddak-data

    cat >/etc/systemd/system/lookddak-data-volume.service <<'UNIT'
    [Unit]
    Description=Mount LookDDak persistent data volume
    After=network-online.target
    Wants=network-online.target

    [Service]
    Type=oneshot
    ExecStart=/usr/local/sbin/mount-lookddak-data
    RemainAfterExit=yes

    [Install]
    WantedBy=multi-user.target
    UNIT

    systemctl daemon-reload
    systemctl enable --now lookddak-data-volume.service
  EOF

  tags = merge(local.common_tags, {
    Name = local.name
  })

  lifecycle {
    # AMI 갱신과 별도 aws_volume_attachment로 관리하는 Data EBS는
    # 인스턴스 본체 교체 사유로 취급하지 않는다.
    ignore_changes = [ami, ebs_block_device]
  }

  depends_on = [aws_iam_role_policy_attachment.ssm_core]
}

resource "aws_volume_attachment" "data" {
  device_name                    = "/dev/sdf"
  volume_id                      = aws_ebs_volume.data.id
  instance_id                    = aws_instance.this.id
  stop_instance_before_detaching = true
}

resource "aws_eip" "this" {
  domain = "vpc"

  tags = merge(local.common_tags, {
    Name = "${local.name}-eip"
  })
}

resource "aws_eip_association" "this" {
  allocation_id = aws_eip.this.id
  instance_id   = aws_instance.this.id

  depends_on = [aws_internet_gateway.this]
}
