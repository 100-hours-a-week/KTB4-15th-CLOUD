output "role_arns" {
  description = "GitOps ServiceAccount에 연결할 Prod V3 워크로드별 IRSA Role ARN"
  value       = { for name, role in aws_iam_role.workload : name => role.arn }
}

output "role_names" {
  description = "Prod V3 워크로드별 IRSA Role 이름"
  value       = { for name, role in aws_iam_role.workload : name => role.name }
}

output "runtime_parameter_names" {
  description = "기존 Prod Queue·S3를 가리키는 V3 전용 Parameter Store 경로"
  value       = { for key, parameter in aws_ssm_parameter.runtime : key => parameter.name }
}
