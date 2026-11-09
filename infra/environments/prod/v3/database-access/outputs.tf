output "parameter_names" {
  description = "Prod V3 database Parameter Store paths"
  value       = local.parameter_names
}

output "bootstrap_document_name" {
  description = "SSM document that creates the Prod V3 database users"
  value       = aws_ssm_document.bootstrap.name
}

output "bootstrap_command" {
  description = "Command that bootstraps the Prod V3 users on the shared databases"
  value       = "aws ssm send-command --region ${data.aws_region.current.region} --instance-ids ${var.db_access_instance_id} --document-name ${aws_ssm_document.bootstrap.name} --comment 'Bootstrap LookDDak Prod V3 shared database users' --query 'Command.CommandId' --output text"
}
