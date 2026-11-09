output "cluster_name" {
  value = aws_eks_cluster.this.name
}

output "cluster_arn" {
  value = aws_eks_cluster.this.arn
}

output "cluster_version" {
  value = aws_eks_cluster.this.version
}

output "cluster_endpoint" {
  value = aws_eks_cluster.this.endpoint
}

output "cluster_certificate_authority_data" {
  value = aws_eks_cluster.this.certificate_authority[0].data
}

output "cluster_security_group_id" {
  description = "EKS가 만든 클러스터 보안그룹 (Control Plane ↔ 노드)"
  value       = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}

output "oidc_provider_arn" {
  value = aws_iam_openid_connect_provider.this.arn
}

output "oidc_issuer" {
  description = "https:// 를 뺀 issuer (IRSA 신뢰 정책 조건 키에 사용)"
  value       = replace(aws_eks_cluster.this.identity[0].oidc[0].issuer, "https://", "")
}

output "api_port_forward_document_name" {
  description = "EKS API SSM 포트포워딩 문서 이름"
  value       = aws_ssm_document.api_port_forward.name
}

output "control_plane_log_group_name" {
  description = "EKS Control Plane CloudWatch 로그 그룹"
  value       = aws_cloudwatch_log_group.cluster.name
}
