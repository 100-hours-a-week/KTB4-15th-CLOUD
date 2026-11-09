# ---------------------------------------------------------------
# V3 prod 네트워크 (EKS)
# - 기존 prod VPC(10.20.0.0/16, V1 소유)에 보조 CIDR을 붙이고 EKS용 서브넷을 만든다.
# - 노드·인프라(EKS 노드, internal NLB, EKS Control Plane ENI)는 기본 CIDR의 node 서브넷.
# - Pod IP는 보조 CIDR(100.64.0.0/16)의 Pod 전용 서브넷 (Cilium ENI 모드가 Pod용 ENI를 여기에 만든다).
# - 외부 경로는 기존 V2 prod 단일 NAT Gateway를 함께 쓴다.
# - 기존 V1/V2 리소스는 변경하지 않는다.
# ---------------------------------------------------------------
locals {
  node_subnets = {
    a = { cidr = "10.20.31.0/24", az = "ap-northeast-2a" }
    c = { cidr = "10.20.32.0/24", az = "ap-northeast-2c" }
  }

  # Pod 서브넷 /18 중 뒤쪽 /19는 Prefix Delegation(/28 블록) 전용으로 예약한다.
  # 앞쪽 /19에는 Pod용 ENI 자신의 Primary IP 같은 개별 IP가 들어간다 → 블록 파편화 방지.
  pod_subnets = {
    a = { cidr = "100.64.0.0/18", az = "ap-northeast-2a", prefix_reservation = "100.64.32.0/19" }
    c = { cidr = "100.64.64.0/18", az = "ap-northeast-2c", prefix_reservation = "100.64.96.0/19" }
  }

  common_tags = {
    Environment = "prod"
    Version     = "v3"
  }
}

# ---------------------------------------------------------------
# 보조 CIDR (Pod 전용)
# ---------------------------------------------------------------
resource "aws_vpc_ipv4_cidr_block_association" "pod" {
  vpc_id     = var.vpc_id
  cidr_block = var.pod_cidr_block
}

# ---------------------------------------------------------------
# Node 서브넷 (기본 CIDR)
# - EKS 노드(eth0), internal NLB(AWS LB Controller), EKS Control Plane ENI
# - internal-elb: AWS LB Controller가 internal LB 서브넷으로 찾는다.
# - karpenter.sh/discovery: Karpenter EC2NodeClass가 노드 서브넷으로 찾는다.
# ---------------------------------------------------------------
resource "aws_subnet" "node" {
  for_each = local.node_subnets

  vpc_id                  = var.vpc_id
  cidr_block              = each.value.cidr
  availability_zone       = each.value.az
  map_public_ip_on_launch = false

  tags = merge(local.common_tags, {
    Name                                        = "lookddak-prod-v3-private-node-${each.key}"
    Tier                                        = "private-node"
    "kubernetes.io/role/internal-elb"           = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "karpenter.sh/discovery"                    = var.cluster_name
  })
}

# ---------------------------------------------------------------
# Pod 서브넷 (보조 CIDR)
# - Tier = private-pod: Cilium ENI 모드가 Pod용 ENI를 만들 서브넷을 이 태그로 찾는다.
# - LB·Karpenter 태그는 붙이지 않는다 (노드·LB가 Pod 대역에 생기지 않게).
# ---------------------------------------------------------------
resource "aws_subnet" "pod" {
  for_each = local.pod_subnets

  vpc_id                  = var.vpc_id
  cidr_block              = each.value.cidr
  availability_zone       = each.value.az
  map_public_ip_on_launch = false

  tags = merge(local.common_tags, {
    Name = "lookddak-prod-v3-private-pod-${each.key}"
    Tier = "private-pod"
  })

  depends_on = [aws_vpc_ipv4_cidr_block_association.pod]
}

resource "aws_ec2_subnet_cidr_reservation" "pod_prefix" {
  for_each = local.pod_subnets

  subnet_id        = aws_subnet.pod[each.key].id
  cidr_block       = each.value.prefix_reservation
  reservation_type = "prefix"
  description      = "Cilium ENI Prefix Delegation (/28) only"
}

# ---------------------------------------------------------------
# 라우팅: node·Pod 서브넷 → V2 prod NAT Gateway
# - 보조 CIDR은 VPC local 경로에 자동 포함된다 (Pod ↔ 노드·RDS 통신에 별도 경로 불필요).
# ---------------------------------------------------------------
resource "aws_route_table" "k8s_private" {
  vpc_id = var.vpc_id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = var.nat_gateway_id
  }

  tags = merge(local.common_tags, {
    Name = "lookddak-prod-v3-private-k8s-rt"
    Tier = "private-k8s"
  })
}

resource "aws_route_table_association" "node" {
  for_each = aws_subnet.node

  subnet_id      = each.value.id
  route_table_id = aws_route_table.k8s_private.id
}

resource "aws_route_table_association" "pod" {
  for_each = aws_subnet.pod

  subnet_id      = each.value.id
  route_table_id = aws_route_table.k8s_private.id
}

# ---------------------------------------------------------------
# S3 Gateway Endpoint (V3 전용)
# - ECR 이미지 레이어, Loki 등 S3 트래픽을 NAT 대신 VPC 경로로 (Gateway Endpoint는 무료).
# - V2 Endpoint는 route_table_ids로 라우팅 테이블을 독점 관리하므로 연결을 추가하지 않고 별도로 만든다.
#   (같은 VPC에 라우팅 테이블이 다르면 S3 Gateway Endpoint를 여러 개 둘 수 있다)
# ---------------------------------------------------------------
data "aws_region" "current" {}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.${data.aws_region.current.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.k8s_private.id]

  tags = merge(local.common_tags, {
    Name = "lookddak-prod-v3-s3-gateway"
  })
}
