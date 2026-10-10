output "instance_id" {
  description = "ID of the V1 application EC2 instance"
  value       = aws_instance.app_v1.id
}

output "instance_arn" {
  description = "ARN of the V1 application EC2 instance"
  value       = aws_instance.app_v1.arn
}

output "private_ip" {
  description = "Private IP address of the V1 application EC2 instance"
  value       = aws_instance.app_v1.private_ip
}

output "public_ip" {
  description = "Elastic IP address of the V1 application EC2 instance"
  value       = aws_eip.app_v1.public_ip
}
