# ---------------------------------------------------------------
# V1 dev 서비스 주소
# ---------------------------------------------------------------
resource "aws_route53_record" "dev" {
  zone_id = var.zone_id
  name    = "dev.lookddak.com"
  type    = "A"
  ttl     = 300
  records = [var.app_public_ip]
}
