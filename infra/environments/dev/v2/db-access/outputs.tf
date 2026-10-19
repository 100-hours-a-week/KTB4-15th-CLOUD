output "instance_id" {
  description = "SSM DB access node instance ID"
  value       = aws_instance.this.id
}

output "instance_private_ip" {
  description = "Private IP of the SSM DB access node"
  value       = aws_instance.this.private_ip
}

output "security_group_id" {
  description = "Security group ID of the SSM DB access node"
  value       = aws_security_group.this.id
}

output "mysql_document_name" {
  description = "Fixed-destination MySQL SSM port-forward document name"
  value       = aws_ssm_document.mysql_port_forward.name
}

output "postgresql_document_name" {
  description = "Fixed-destination PostgreSQL SSM port-forward document name"
  value       = aws_ssm_document.postgresql_port_forward.name
}

output "mysql_port_forward_command" {
  description = "CLI command for the shared test user to open the Dev MySQL tunnel"
  value       = "aws ssm start-session --profile <team-profile> --region ${data.aws_region.current.region} --target ${aws_instance.this.id} --document-name ${aws_ssm_document.mysql_port_forward.name} --parameters '${jsonencode({ localPortNumber = ["13306"] })}'"
}

output "postgresql_port_forward_command" {
  description = "CLI command for the shared test user to open the Dev PostgreSQL tunnel"
  value       = "aws ssm start-session --profile <team-profile> --region ${data.aws_region.current.region} --target ${aws_instance.this.id} --document-name ${aws_ssm_document.postgresql_port_forward.name} --parameters '${jsonencode({ localPortNumber = ["15432"] })}'"
}

