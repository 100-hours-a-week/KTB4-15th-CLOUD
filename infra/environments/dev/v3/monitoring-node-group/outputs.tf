output "node_group_name" {
  description = "Monitoring Managed Node Group 이름"
  value       = aws_eks_node_group.monitoring.node_group_name
}

output "node_role_arn" {
  description = "Monitoring Node가 사용하는 IAM Role ARN"
  value       = aws_iam_role.monitoring_node.arn
}
