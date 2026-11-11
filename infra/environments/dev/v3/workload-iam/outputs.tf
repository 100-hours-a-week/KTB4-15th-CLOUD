output "role_arns" {
  description = "GitOps ServiceAccount에 연결할 V3 Dev 워크로드별 IRSA Role ARN"
  value       = { for name, role in aws_iam_role.workload : name => role.arn }
}

output "role_names" {
  description = "V3 Dev 워크로드별 IRSA Role 이름"
  value       = { for name, role in aws_iam_role.workload : name => role.name }
}

output "idm_vton_modal_parameter_names" {
  description = "실제 Modal SDK Token을 수동 입력할 Dev SecureString 경로"
  value       = { for key, parameter in aws_ssm_parameter.idm_vton_modal : key => parameter.name }
}
