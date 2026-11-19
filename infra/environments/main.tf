module "dev_single_ec2" {
  source = "./dev/single-ec2"
}

module "dev_single_runtime" {
  source = "./dev/single-runtime"

  instance_role_name = module.dev_single_ec2.instance_role_name
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

output "dev_single_runtime" {
  description = "Single Dev runtime AWS resource information"
  value = {
    ecr_repository_urls   = module.dev_single_runtime.ecr_repository_urls
    images_bucket_name    = module.dev_single_runtime.images_bucket_name
    backup_bucket_name    = module.dev_single_runtime.backup_bucket_name
    fitting_queue_urls    = module.dev_single_runtime.fitting_queue_urls
    log_group_name        = module.dev_single_runtime.log_group_name
    runtime_parameter_arn = module.dev_single_runtime.runtime_parameter_arn
  }
}
