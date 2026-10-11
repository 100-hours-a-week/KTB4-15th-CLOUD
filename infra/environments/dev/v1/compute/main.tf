# ---------------------------------------------------------------
# V1 dev 애플리케이션 서버
# - prod EC2(prod/v1/compute)와 같은 AMI·인스턴스 타입·디스크·메타데이터 설정
# - 차이: dev VPC 사용, 종료 보호 해제(다시 만들 수 있도록), 고정 private IP 없음
# ---------------------------------------------------------------
resource "aws_instance" "app_v1" {
  ami                         = "ami-0c00138a007c968d8"
  instance_type               = "t4g.medium"
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [var.security_group_id]
  iam_instance_profile        = var.iam_instance_profile_name
  associate_public_ip_address = true
  disable_api_termination     = false # dev는 다시 만들 수 있도록 끔 (prod: true)
  monitoring                  = false

  credit_specification {
    cpu_credits = "unlimited"
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
    instance_metadata_tags      = "disabled"
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 30
    iops                  = 3000
    throughput            = 125
    encrypted             = true
    delete_on_termination = true

    tags = {
      Name        = "lookddak-dev-app-v1-root"
      Environment = "dev"
      Project     = "lookddak"
      ManagedBy   = "terraform"
      Role        = "app"
    }
  }

  tags = {
    Name        = "lookddak-dev-app-v1"
    Environment = "dev"
    Role        = "app"
  }
}

resource "aws_eip" "app_v1" {
  domain = "vpc"

  tags = {
    Name        = "lookddak-dev-app-v1-eip"
    Environment = "dev"
    Role        = "app"
  }
}

resource "aws_eip_association" "app_v1" {
  allocation_id = aws_eip.app_v1.id
  instance_id   = aws_instance.app_v1.id
}
