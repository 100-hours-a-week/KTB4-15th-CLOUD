output "ec2_instance_profile_name" {
  description = "Name of the V1 EC2 instance profile"
  value       = aws_iam_instance_profile.ec2.name
}

output "deploy_role_names" {
  description = "Names of the V1 application deployment roles"
  value = {
    fe = aws_iam_role.fe_deploy.name
    be = aws_iam_role.be_deploy.name
    ai = aws_iam_role.ai_deploy.name
  }
}
