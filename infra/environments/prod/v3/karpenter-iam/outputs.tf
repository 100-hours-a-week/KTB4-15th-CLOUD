output "controller_role_arn" {
  description = "Karpenter Controller ServiceAccount에 연결할 IRSA Role ARN"
  value       = aws_iam_role.controller.arn
}

output "node_role_arn" {
  description = "Karpenter가 생성하는 EC2 Node의 IAM Role ARN"
  value       = aws_iam_role.node.arn
}

output "node_instance_profile_name" {
  description = "EC2NodeClass spec.instanceProfile에서 사용할 Instance Profile 이름"
  value       = aws_iam_instance_profile.node.name
}

output "node_access_entry_arn" {
  description = "Karpenter Node Role의 EKS Access Entry ARN"
  value       = aws_eks_access_entry.node.access_entry_arn
}
