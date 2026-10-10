output "ec2_instance_profile_name" {
  description = "Name of the V1 EC2 instance profile"
  value       = aws_iam_instance_profile.ec2.name
}
