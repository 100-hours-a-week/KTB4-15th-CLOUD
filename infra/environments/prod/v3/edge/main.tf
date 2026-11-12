# Client → CloudFront + WAF → VPC Origin → Internal NLB → Istio Gateway → Argo CD
locals {
  name = "lookddak-prod-v3-argocd"

  common_tags = {
    Environment = "prod"
    Version     = "v3"
    Component   = "argocd-edge"
  }
}

# NLB는 GitOps의 Gateway Service와 AWS Load Balancer Controller가 소유한다.
# Terraform은 Kubernetes 태그로 조회만 하며 소유권을 가져오지 않는다.
data "aws_lb" "gateway" {
  tags = {
    "elbv2.k8s.aws/cluster"    = var.cluster_name
    "service.k8s.aws/stack"    = var.gateway_service
    "service.k8s.aws/resource" = "LoadBalancer"
  }
}

# CloudFront VPC Origin의 공식 선행 조건에 맞춰 Origin 전용 SG를 만든다.
# 적용 뒤 출력되는 SG ID를 GitOps Gateway Service annotation에 연결한다.
data "aws_ec2_managed_prefix_list" "cloudfront" {
  name = "com.amazonaws.global.cloudfront.origin-facing"
}

resource "aws_security_group" "gateway_nlb" {
  name        = "${local.name}-gateway-nlb"
  description = "Prod Argo CD Gateway NLB - CloudFront VPC Origin only"
  vpc_id      = var.vpc_id

  tags = merge(local.common_tags, {
    Name = "${local.name}-gateway-nlb"
  })
}

resource "aws_vpc_security_group_ingress_rule" "gateway_nlb_cloudfront" {
  security_group_id = aws_security_group.gateway_nlb.id
  description       = "HTTPS from CloudFront origin-facing servers"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  prefix_list_id    = data.aws_ec2_managed_prefix_list.cloudfront.id
}

resource "aws_vpc_security_group_egress_rule" "gateway_nlb_all" {
  security_group_id = aws_security_group.gateway_nlb.id
  description       = "To Istio Gateway Pods"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# CloudFront Viewer 인증서는 us-east-1에 있어야 한다.
resource "aws_acm_certificate" "viewer" {
  provider = aws.us_east_1

  domain_name               = var.domain_name
  subject_alternative_names = sort(tolist(var.additional_domain_names))
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
    if !contains(var.prevalidated_domain_names, option.domain_name)
  }

  zone_id = var.route53_zone_id
  name    = each.value.name
  type    = each.value.type
  ttl     = 300
  records = [each.value.record]
}

resource "aws_acm_certificate_validation" "viewer" {
  provider = aws.us_east_1

  certificate_arn = aws_acm_certificate.viewer.arn
  validation_record_fqdns = concat(
    [for record in aws_route53_record.viewer_validation : record.fqdn],
    [
      for option in aws_acm_certificate.viewer.domain_validation_options : option.resource_record_name
      if contains(var.prevalidated_domain_names, option.domain_name)
    ]
  )
}

# 값 자체보다 리소스 의존성이 목적이다. 기존 V2 Distribution 업데이트가 끝난 뒤
# 동일 Alias를 V3 Distribution에 붙여 CNAMEAlreadyExists를 방지한다.
resource "terraform_data" "alias_release" {
  input = var.cutover_after_distribution_id
}

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

  lifecycle {
    precondition {
      condition     = data.aws_lb.gateway.internal && data.aws_lb.gateway.load_balancer_type == "network"
      error_message = "Prod Gateway Origin은 Internal NLB여야 합니다."
    }
  }

  depends_on = [aws_vpc_security_group_ingress_rule.gateway_nlb_cloudfront]

  tags = merge(local.common_tags, {
    Name = "${local.name}-gateway"
  })
}

data "aws_cloudfront_cache_policy" "caching_disabled" {
  name = "Managed-CachingDisabled"
}

# Host 전달은 Gateway Listener와 HTTPRoute의 hostname 매칭에 필요하다.
data "aws_cloudfront_origin_request_policy" "all_viewer" {
  name = "Managed-AllViewer"
}

resource "aws_cloudfront_distribution" "this" {
  enabled         = true
  is_ipv6_enabled = true
  http_version    = "http2and3"
  price_class     = "PriceClass_200"
  comment         = "LookDDak Prod V3 Edge"
  aliases         = concat([var.domain_name], sort(tolist(var.additional_domain_names)))
  web_acl_id      = aws_wafv2_web_acl.argocd.arn

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

  depends_on = [terraform_data.alias_release]
}

resource "aws_route53_record" "alias" {
  for_each = toset(["A", "AAAA"])

  zone_id = var.route53_zone_id
  name    = var.domain_name
  type    = each.value

  alias {
    name                   = aws_cloudfront_distribution.this.domain_name
    zone_id                = aws_cloudfront_distribution.this.hosted_zone_id
    evaluate_target_health = false
  }
}

# 기존 Argo CD A·AAAA 레코드의 State 주소는 유지하고 검증 도메인만 별도 추가한다.
resource "aws_route53_record" "additional_alias" {
  for_each = toset(flatten([
    for domain in var.additional_domain_names : ["${domain}|A", "${domain}|AAAA"]
  ]))

  zone_id = var.route53_zone_id
  name    = split("|", each.value)[0]
  type    = split("|", each.value)[1]

  alias {
    name                   = aws_cloudfront_distribution.this.domain_name
    zone_id                = aws_cloudfront_distribution.this.hosted_zone_id
    evaluate_target_health = false
  }
}
