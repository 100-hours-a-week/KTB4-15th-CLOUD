module "dev_single_ec2" {
  source = "./dev/single-ec2"
}

output "dev_single_ec2" {
  description = "Single Dev EC2 connection and network information"
  value = {
    instance_id       = module.dev_single_ec2.instance_id
    elastic_ip        = module.dev_single_ec2.elastic_ip
    data_volume_id    = module.dev_single_ec2.data_volume_id
    ssm_start_command = module.dev_single_ec2.ssm_start_command
    application_path  = module.dev_single_ec2.application_path
  }
}
