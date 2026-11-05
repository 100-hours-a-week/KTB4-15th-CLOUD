# ---------------------------------------------------------------
# V3 dev Edge
# Client → CloudFront (ACM us-east-1) → VPC Origin → 내부 NLB (TCP 443) → Istio Gateway (TLS 종료)
# - NLB는 GITOPS의 Istio Gateway Service를 보고 AWS LB Controller가 만든다. 여기서는 태그로 조회만 한다
# - CloudFront는 viewer Host를 전달하고, Gateway 인증서(Let's Encrypt)를 그 Host로 검증한다
# ---------------------------------------------------------------
locals {
  name = "lookddak-dev-v3"

  common_tags = {
    Environment = "dev"
    Version     = "v3"
  }
}

data "aws_lb" "gateway" {
  tags = {
    "elbv2.k8s.aws/cluster"    = var.cluster_name
    "service.k8s.aws/stack"    = var.gateway_service
    "service.k8s.aws/resource" = "LoadBalancer"
  }
}

# ---------------------------------------------------------------
# NLB 보안그룹: CloudFront(origin-facing)에서 오는 443만 허용
# - GITOPS Gateway 어노테이션(aws-load-balancer-security-groups)으로 NLB에 붙인다
# - Pod 쪽 허용 규칙은 AWS LB Controller가 관리한다 (manage-backend-security-group-rules)
# ---------------------------------------------------------------
data "aws_ec2_managed_prefix_list" "cloudfront" {
  name = "com.amazonaws.global.cloudfront.origin-facing"
}

resource "aws_security_group" "gateway_nlb" {
  name        = "${local.name}-gateway-nlb"
  description = "Istio Gateway NLB - CloudFront VPC Origin only"
  vpc_id      = var.vpc_id

  tags = merge(local.common_tags, {
    Name = "${local.name}-gateway-nlb"
  })
}

resource "aws_vpc_security_group_ingress_rule" "gateway_nlb_cloudfront" {
  security_group_id = aws_security_group.gateway_nlb.id
  description       = "HTTPS from CloudFront"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  prefix_list_id    = data.aws_ec2_managed_prefix_list.cloudfront.id
}

resource "aws_vpc_security_group_egress_rule" "gateway_nlb_all" {
  security_group_id = aws_security_group.gateway_nlb.id
  description       = "To Gateway Pods (443, health check 15021)"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# ---------------------------------------------------------------
# CloudFront 뷰어 인증서 (us-east-1)
# ---------------------------------------------------------------
resource "aws_acm_certificate" "viewer" {
  provider = aws.us_east_1

  domain_name               = var.domain_names[0]
  subject_alternative_names = slice(var.domain_names, 1, length(var.domain_names))
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(local.common_tags, {
    Name = "${local.name}-viewer"
  })
}

resource "aws_route53_record" "viewer_validation" {
  for_each = {
    for option in aws_acm_certificate.viewer.domain_validation_options :
    option.domain_name => {
      name   = option.resource_record_name
      record = option.resource_record_value
      type   = option.resource_record_type
    }
  }

  zone_id = var.route53_zone_id
  name    = each.value.name
  type    = each.value.type
  ttl     = 300
  records = [each.value.record]
}

resource "aws_acm_certificate_validation" "viewer" {
  provider = aws.us_east_1

  certificate_arn         = aws_acm_certificate.viewer.arn
  validation_record_fqdns = [for record in aws_route53_record.viewer_validation : record.fqdn]
}

# ---------------------------------------------------------------
# CloudFront VPC Origin → 내부 NLB
# ---------------------------------------------------------------
resource "aws_cloudfront_vpc_origin" "gateway" {
  vpc_origin_endpoint_config {
    name                   = "${local.name}-gateway"
    arn                    = data.aws_lb.gateway.arn
    http_port              = 80
    https_port             = 443
    origin_protocol_policy = "https-only"

    origin_ssl_protocols {
      items    = ["TLSv1.2"]
      quantity = 1
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.name}-gateway"
  })
}

data "aws_cloudfront_cache_policy" "caching_disabled" {
  name = "Managed-CachingDisabled"
}

# Host 포함: Gateway 인증서 검증과 Listener·HTTPRoute 매칭에 필요하다
data "aws_cloudfront_origin_request_policy" "all_viewer" {
  name = "Managed-AllViewer"
}

resource "aws_cloudfront_distribution" "this" {
  enabled         = true
  is_ipv6_enabled = true
  http_version    = "http2and3"
  price_class     = "PriceClass_200"
  comment         = "LookDDak dev v3"
  aliases         = var.domain_names

  origin {
    domain_name = data.aws_lb.gateway.dns_name
    origin_id   = "${local.name}-gateway"

    vpc_origin_config {
      vpc_origin_id            = aws_cloudfront_vpc_origin.gateway.id
      origin_keepalive_timeout = 60
      origin_read_timeout      = var.origin_read_timeout
    }
  }

  default_cache_behavior {
    target_origin_id       = "${local.name}-gateway"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    cache_policy_id          = data.aws_cloudfront_cache_policy.caching_disabled.id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_viewer.id
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.viewer.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  tags = merge(local.common_tags, {
    Name = local.name
  })
}

# ---------------------------------------------------------------
# DNS: 도메인 → CloudFront
# ---------------------------------------------------------------
resource "aws_route53_record" "alias" {
  for_each = toset(flatten([for domain in var.domain_names : ["${domain}|A", "${domain}|AAAA"]]))

  zone_id = var.route53_zone_id
  name    = split("|", each.value)[0]
  type    = split("|", each.value)[1]

  alias {
    name                   = aws_cloudfront_distribution.this.domain_name
    zone_id                = aws_cloudfront_distribution.this.hosted_zone_id
    evaluate_target_health = false
  }
}
