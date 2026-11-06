output "role_arns" {
  description = "GitOps ServiceAccount에 연결할 V3 Dev 워크로드별 IRSA Role ARN"
  value       = { for name, role in aws_iam_role.workload : name => role.arn }
}

output "role_names" {
  description = "V3 Dev 워크로드별 IRSA Role 이름"
  value       = { for name, role in aws_iam_role.workload : name => role.name }
}
