output "ec2_instance_profile_name" {
  description = "dev EC2 인스턴스 프로파일 이름"
  value       = aws_iam_instance_profile.ec2.name
}
