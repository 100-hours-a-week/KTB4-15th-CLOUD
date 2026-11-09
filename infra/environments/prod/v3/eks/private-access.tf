# ---------------------------------------------------------------
# private API 엔드포인트 접근 (Monitoring EC2 SSM 포트포워딩)
# - 로컬 → SSM → prod Monitoring EC2 → EKS API 엔드포인트(443)
# - kubectl/helm 인증은 로컬 IAM 주체(Access Entry)로 한다. bastion Role에는 클러스터 권한을 주지 않는다.
# - bastion 보안그룹 egress 443(0.0.0.0/0)은 이미 있다 (SSM 연결용).
# ---------------------------------------------------------------
resource "aws_vpc_security_group_ingress_rule" "api_from_ssm_instance" {
  security_group_id            = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
  description                  = "EKS API from prod monitoring EC2 (SSM port forwarding)"
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  referenced_security_group_id = var.api_access_security_group_id

  tags = local.common_tags
}

# 목적지(EKS API 엔드포인트:443)를 고정한 포트포워딩 문서. 로컬 포트만 고를 수 있다.
resource "aws_ssm_document" "api_port_forward" {
  name            = "${var.cluster_name}-api-port-forward"
  document_type   = "Session"
  document_format = "JSON"

  content = jsonencode({
    schemaVersion = "1.0"
    description   = "Forward local port 9443 to the ${var.cluster_name} EKS private API endpoint"
    sessionType   = "Port"
    parameters = {
      localPortNumber = {
        type           = "String"
        description    = "Fixed local Kubernetes API listener port"
        default        = "9443"
        allowedPattern = "^9443$"
      }
    }
    properties = {
      type            = "LocalPortForwarding"
      host            = replace(aws_eks_cluster.this.endpoint, "https://", "")
      portNumber      = "443"
      localPortNumber = "{{ localPortNumber }}"
    }
  })

  tags = local.common_tags
}
