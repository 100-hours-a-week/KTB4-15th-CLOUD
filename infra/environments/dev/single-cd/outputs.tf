output "deploy_role_arns" {
  description = "GitHub OIDC deploy role ARN per service (set as AWS_DEPLOY_ROLE_ARN in each app repository)"
  value       = { for name, role in aws_iam_role.deploy : name => role.arn }
}

output "update_document_names" {
  description = "SSM document name per service used by app CD"
  value       = { for name, doc in aws_ssm_document.update_image : name => doc.name }
}
