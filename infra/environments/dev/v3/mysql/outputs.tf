output "database_name" {
  description = "V3 Spring 워크로드 전용 MySQL Database 이름"
  value       = local.database_name
}

output "parameter_names" {
  description = "V3 Spring 워크로드가 사용할 MySQL Parameter Store 경로"
  value       = local.parameter_names
}

output "bootstrap_document_name" {
  description = "V3 MySQL Database와 사용자를 구성하는 SSM Document 이름"
  value       = aws_ssm_document.bootstrap.name
}

output "bootstrap_command" {
  description = "V3 MySQL Database와 사용자를 최초 1회 구성하는 명령"
  value       = "aws ssm send-command --region ${data.aws_region.current.region} --instance-ids ${var.db_access_instance_id} --document-name ${aws_ssm_document.bootstrap.name} --comment 'Bootstrap LookDDak Dev V3 MySQL' --query 'Command.CommandId' --output text"
}
