output "node_group_name" {
  description = "System Managed Node Group 이름"
  value       = aws_eks_node_group.system.node_group_name
}

output "node_role_arn" {
  description = "System Node가 사용하는 IAM Role ARN"
  value       = aws_iam_role.system_node.arn
}

output "launch_template_id" {
  description = "System Node Launch Template ID"
  value       = aws_launch_template.system.id
}

output "launch_template_version" {
  description = "System Node Launch Template 최신 버전"
  value       = aws_launch_template.system.latest_version
}
