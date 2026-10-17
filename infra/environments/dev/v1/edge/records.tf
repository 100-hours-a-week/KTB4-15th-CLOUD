# ---------------------------------------------------------------
# V1 dev 서비스 주소
# - dev.lookddak.com -> V2 dev ALB -> (host 규칙) V1 dev EC2 nginx
# - V2 전환 시 ALB 규칙만 바꾸고 이 레코드는 그대로 둔다.
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
