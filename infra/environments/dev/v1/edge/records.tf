# ---------------------------------------------------------------
# Dev 기본 서비스 주소
# - dev.lookddak.com -> V2 dev ALB
# - 실제 V1/V2 대상 선택은 ALB host/path 규칙에서 관리한다.
# - V2 전환 시에도 이 Route53 레코드는 변경하지 않는다.
# ---------------------------------------------------------------
resource "aws_route53_record" "dev" {
  zone_id = var.zone_id
  name    = "dev.lookddak.com"
  type    = "A"

  alias {
    name                   = var.alb_dns_name
    zone_id                = var.alb_zone_id
    evaluate_target_health = false
  }
}
