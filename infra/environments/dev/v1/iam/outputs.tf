output "ec2_instance_profile_name" {
  description = "dev EC2 인스턴스 프로파일 이름"
  value       = aws_iam_instance_profile.ec2.name
}

output "deploy_role_names" {
  description = "dev 앱 배포 Role 이름 (서비스 키 => Role 이름)"
  value       = { for k, r in aws_iam_role.deploy : k => r.name }
}

output "cicd_role_arns" {
  description = "앱 레포 GitHub Variables에 등록할 dev CD Role ARN"
  value = {
    for k in keys(local.cicd_services) : k => {
      build  = aws_iam_role.build[k].arn
      deploy = aws_iam_role.deploy[k].arn
    }
  }
}
