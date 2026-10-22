# -----------------------------------------------------------------------------
# Production hostname (lookddak.com) -> V2 CloudFront
# - 2026-10-22 V1 -> V2 전환: V1 EC2 Elastic IP A 레코드를 CloudFront alias로 교체.
# - A 레코드는 prod/v1/edge의 apex에서 옮겼다 (root moved 블록, in-place 변경).
# - www.lookddak.com은 prod/v1/edge의 CNAME(→ lookddak.com)을 그대로 쓴다.
# - 롤백: 이 변경을 revert하면 V1 EIP A 레코드로 돌아간다.
# -----------------------------------------------------------------------------
resource "aws_route53_record" "production_ipv4" {
  zone_id = var.route53_zone_id
  name    = var.production_domain_name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.this.domain_name
    zone_id                = aws_cloudfront_distribution.this.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "production_ipv6" {
  zone_id = var.route53_zone_id
  name    = var.production_domain_name
  type    = "AAAA"

  alias {
    name                   = aws_cloudfront_distribution.this.domain_name
    zone_id                = aws_cloudfront_distribution.this.hosted_zone_id
    evaluate_target_health = false
  }
}
