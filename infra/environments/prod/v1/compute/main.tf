resource "aws_instance" "app_v1" {
  ami                                  = "ami-0c00138a007c968d8"
  instance_type                        = "t4g.medium"
  subnet_id                            = var.subnet_id
  private_ip                           = "10.20.1.203"
  vpc_security_group_ids               = [var.security_group_id]
  iam_instance_profile                 = var.iam_instance_profile_name
  associate_public_ip_address          = true
  disable_api_stop                     = false
  disable_api_termination              = true
  ebs_optimized                        = false
  hibernation                          = false
  instance_initiated_shutdown_behavior = "stop"
  monitoring                           = false
  source_dest_check                    = true

  capacity_reservation_specification {
    capacity_reservation_preference = "open"
  }

  cpu_options {
    core_count       = 2
    threads_per_core = 1
  }

  credit_specification {
    cpu_credits = "unlimited"
  }

  enclave_options {
    enabled = false
  }

  maintenance_options {
    auto_recovery = "default"
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_protocol_ipv6          = "disabled"
    http_put_response_hop_limit = 2
    http_tokens                 = "required"
    instance_metadata_tags      = "disabled"
  }

  private_dns_name_options {
    enable_resource_name_dns_a_record    = false
    enable_resource_name_dns_aaaa_record = false
    hostname_type                        = "ip-name"
  }

  root_block_device {
    delete_on_termination = true
    encrypted             = true
    iops                  = 3000
    kms_key_id            = "arn:aws:kms:ap-northeast-2:686496667254:key/78007427-4b73-49a3-8832-3ac866fb2d9d"
    throughput            = 125
    volume_size           = 30
    volume_type           = "gp3"

    tags = {
      Backup      = "daily"
      Environment = "prod"
      ManagedBy   = "aws-cli"
      Name        = "lookddak-app-v1-root"
      Project     = "lookddak"
      Role        = "app"
    }
  }

  tags = {
    Backup      = "daily"
    Environment = "prod"
    ManagedBy   = "aws-cli"
    Name        = "lookddak-app-v1"
    Role        = "app"
  }

  lifecycle {
    prevent_destroy = true
    ignore_changes = [
      tags,
      tags_all,
      root_block_device[0].tags,
      root_block_device[0].tags_all,
    ]
  }
}

resource "aws_eip" "app_v1" {
  domain               = "vpc"
  network_border_group = "ap-northeast-2"
  public_ipv4_pool     = "amazon"

  tags = {
    Environment = "prod"
    ManagedBy   = "aws-cli"
    Name        = "lookddak-app-v1-eip"
    Role        = "app"
  }

  lifecycle {
    prevent_destroy = true
    ignore_changes  = [tags, tags_all]
  }
}

resource "aws_eip_association" "app_v1" {
  allocation_id      = aws_eip.app_v1.id
  instance_id        = aws_instance.app_v1.id
  private_ip_address = aws_instance.app_v1.private_ip
}
