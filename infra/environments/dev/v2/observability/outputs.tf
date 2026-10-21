output "instance_id" {
  description = "Monitoring server instance ID"
  value       = aws_instance.this.id
}

output "private_ip" {
  description = "Fixed private IP of the monitoring server"
  value       = aws_instance.this.private_ip
}

output "security_group_id" {
  description = "Monitoring server security group ID"
  value       = aws_security_group.this.id
}

output "instance_role_name" {
  description = "Monitoring server IAM role name"
  value       = aws_iam_role.instance.name
}
