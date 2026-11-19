output "instance_id" {
  description = "Single Dev EC2 instance ID"
  value       = aws_instance.this.id
}

output "elastic_ip" {
  description = "Stable public IPv4 address"
  value       = aws_eip.this.public_ip
}

output "vpc_id" {
  description = "Single Dev VPC ID"
  value       = aws_vpc.this.id
}

output "public_subnet_id" {
  description = "Single Dev public subnet ID"
  value       = aws_subnet.public.id
}

output "security_group_id" {
  description = "EC2 security group ID"
  value       = aws_security_group.instance.id
}

output "data_volume_id" {
  description = "Persistent encrypted data EBS volume ID"
  value       = aws_ebs_volume.data.id
}

output "application_path" {
  description = "Persistent application mount path"
  value       = local.application_path
}

output "ssm_start_command" {
  description = "Session Manager connection command"
  value       = "aws ssm start-session --profile lookddak --region ap-northeast-2 --target ${aws_instance.this.id}"
}
