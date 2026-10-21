data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

data "aws_region" "current" {}

data "aws_subnet" "this" {
  id = var.subnet_id
}

data "aws_ssm_parameter" "al2023_arm64" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
}

locals {
  name       = "lookddak-dev-monitoring"
  private_ip = cidrhost(data.aws_subnet.this.cidr_block, var.private_ip_host_number)

  common_tags = {
    Component   = "monitoring"
    Environment = "dev"
    Version     = "v2"
  }
}

# ---------------------------------------------------------------
# Network
# - Session Manager로만 접속하므로 지금은 인바운드 규칙이 없다.
#   (Grafana ALB, 로그 수신 포트는 이후 PR에서 추가)
# - 아웃바운드는 HTTPS만 연다: SSM, CloudWatch·ECS API, 컨테이너 이미지·패키지 다운로드
# ---------------------------------------------------------------
resource "aws_security_group" "this" {
  name                   = "${local.name}-sg"
  description            = "LookDDak dev monitoring server"
  vpc_id                 = var.vpc_id
  revoke_rules_on_delete = true

  tags = merge(local.common_tags, {
    Name = "${local.name}-sg"
  })
}

resource "aws_vpc_security_group_egress_rule" "https" {
  security_group_id = aws_security_group.this.id
  description       = "HTTPS to AWS APIs and image registries through the existing NAT Gateway"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

# ---------------------------------------------------------------
# EC2 instance role
# - SSM 접속
# - 읽기 전용 관측 권한: CloudWatch 메트릭(YACE), 리소스 태그 탐색,
#   ECS task 조회(Prometheus ECS 서비스 디스커버리), CloudWatch Logs 조회(Grafana)
# - /lookddak/dev/monitoring/* 파라미터 읽기 (Grafana 관리자 비밀번호 등, 콘솔에서 수동 생성)
# ---------------------------------------------------------------
resource "aws_iam_role" "instance" {
  name        = "${local.name}-instance-role"
  description = "LookDDak dev monitoring server"

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

resource "aws_iam_role_policy" "observability_read" {
  name = "observability-read"
  role = aws_iam_role.instance.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "CloudWatchMetricsRead"
      Effect = "Allow"
      Action = [
        "cloudwatch:GetMetricData",
        "cloudwatch:GetMetricStatistics",
        "cloudwatch:ListMetrics",
        "tag:GetResources",
      ]
      Resource = "*"
      }, {
      Sid    = "EcsServiceDiscovery"
      Effect = "Allow"
      Action = [
        "ecs:ListClusters",
        "ecs:DescribeClusters",
        "ecs:ListServices",
        "ecs:DescribeServices",
        "ecs:ListTasks",
        "ecs:DescribeTasks",
      ]
      Resource = "*"
      }, {
      Sid    = "CloudWatchLogsQuery"
      Effect = "Allow"
      Action = [
        "logs:DescribeLogGroups",
        "logs:GetLogGroupFields",
        "logs:StartQuery",
        "logs:StopQuery",
        "logs:GetQueryResults",
        "logs:GetLogEvents",
        "logs:FilterLogEvents",
      ]
      Resource = "*"
      }, {
      Sid      = "MonitoringParameters"
      Effect   = "Allow"
      Action   = "ssm:GetParameter"
      Resource = "arn:${data.aws_partition.current.partition}:ssm:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:parameter/lookddak/dev/monitoring/*"
    }]
  })
}

resource "aws_iam_instance_profile" "this" {
  name = "${local.name}-instance-profile"
  role = aws_iam_role.instance.name

  tags = local.common_tags
}

# ---------------------------------------------------------------
# Monitoring server
# - 고정 private IP: 이후 로그·트레이스를 보내는 쪽(Fluent Bit 등)이 이 주소를 쓴다.
# - IMDS hop limit 2: Docker 컨테이너(Alloy 등)가 인스턴스 역할을 쓰기 위해 필요
# - 디스크는 루트 하나만 쓴다 (dev). Loki 로그는 S3에 두고,
#   Prometheus·Grafana 데이터는 인스턴스 교체 시 유실을 감수한다.
#   디스크가 가득 차지 않도록 Prometheus 용량 상한, Docker 로그 상한을 둔다.
# ---------------------------------------------------------------
resource "aws_instance" "this" {
  ami                         = data.aws_ssm_parameter.al2023_arm64.value
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  private_ip                  = local.private_ip
  vpc_security_group_ids      = [aws_security_group.this.id]
  iam_instance_profile        = aws_iam_instance_profile.this.name
  associate_public_ip_address = false
  key_name                    = null

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size
    encrypted             = true
    delete_on_termination = true
  }

  # 처음 부팅할 때 한 번만 실행된다. 자주 바뀌는 모니터링 설정은 SSM으로 따로 배포한다.
  user_data = <<-EOF
    #!/bin/bash
    set -euxo pipefail

    systemctl enable --now amazon-ssm-agent

    # Docker: 루트 디스크 하나만 쓰므로 컨테이너 로그에 상한을 둔다.
    dnf install -y docker
    mkdir -p /etc/docker
    cat > /etc/docker/daemon.json <<'JSON'
    {"log-driver": "json-file", "log-opts": {"max-size": "10m", "max-file": "3"}}
    JSON
    systemctl enable --now docker

    # Docker Compose plugin
    mkdir -p /usr/local/lib/docker/cli-plugins
    curl -fsSL https://github.com/docker/compose/releases/download/v2.29.7/docker-compose-linux-aarch64 \
      -o /usr/local/lib/docker/cli-plugins/docker-compose
    chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

    mkdir -p /opt/monitoring
  EOF

  tags = merge(local.common_tags, {
    Name = local.name
  })

  # AMI 파라미터가 갱신될 때마다 교체되지 않게 한다. 교체는 의도할 때만.
  lifecycle {
    ignore_changes = [ami]
  }

  depends_on = [aws_iam_role_policy_attachment.ssm_core]
}
