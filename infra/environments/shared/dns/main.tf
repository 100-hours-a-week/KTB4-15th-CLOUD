terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      configuration_aliases = [aws.us_east_1]
    }
  }
}

locals {
  domain_name = "lookddak.com"

  common_tags = {
    Component   = "dns"
    Environment = "shared"
    Purpose     = "public-domain"
  }
}

# ---------------------------------------------------------------
# Hosted Zone
# - dev·prod 전체 삭제(#533)로 기존 Zone이 삭제되어 다시 생성한다.
# - NS, SOA 레코드는 Zone과 함께 AWS가 관리한다.
# ---------------------------------------------------------------
resource "aws_route53_zone" "main" {
  name    = local.domain_name
  comment = "LookDDak public hosted zone"

  tags = merge(local.common_tags, {
    Name = local.domain_name
  })
}

# ---------------------------------------------------------------
# 메일 (ImprovMX) - 기존 shared_core 레코드 복원
# ---------------------------------------------------------------
resource "aws_route53_record" "mx" {
  zone_id = aws_route53_zone.main.zone_id
  name    = local.domain_name
  type    = "MX"
  ttl     = 300
  records = [
    "10 mx1.improvmx.com",
    "20 mx2.improvmx.com",
  ]
}

resource "aws_route53_record" "spf" {
  zone_id = aws_route53_zone.main.zone_id
  name    = local.domain_name
  type    = "TXT"
  ttl     = 300
  records = ["v=spf1 include:spf.improvmx.com ~all"]
}

# ---------------------------------------------------------------
# Single Dev
# ---------------------------------------------------------------
resource "aws_route53_record" "dev" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "dev.${local.domain_name}"
  type    = "A"
  ttl     = 300
  records = [var.dev_single_public_ip]
}

# ---------------------------------------------------------------
# Registrar name servers
# - Route53 Domains API는 us-east-1에서만 제공된다.
# - 도메인 등록 자체는 관리하지 않으며 destroy 시에도 등록은 유지된다.
# - 리소스 기본값(auto_renew·transfer_lock = true)이 적용되지 않도록 현재 등록 설정을 그대로 명시한다.
#   (자동 갱신을 켜면 만료 시 비용이 자동 결제된다)
# ---------------------------------------------------------------
resource "aws_route53domains_registered_domain" "main" {
  provider = aws.us_east_1

  domain_name = local.domain_name

  auto_renew         = false
  transfer_lock      = false
  admin_privacy      = true
  registrant_privacy = true
  tech_privacy       = true
  billing_privacy    = true

  dynamic "name_server" {
    for_each = aws_route53_zone.main.name_servers

    content {
      name = name_server.value
    }
  }
}
