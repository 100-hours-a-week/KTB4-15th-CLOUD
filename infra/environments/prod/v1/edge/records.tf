# ---------------------------------------------------------------
# V1 서비스 주소 레코드
# V2 전환 시 CloudFront를 가리키는 레코드로 교체된다.
# ---------------------------------------------------------------
resource "aws_route53_record" "apex" {
  zone_id = var.zone_id
  name    = "lookddak.com"
  type    = "A"
  ttl     = 300
  records = [var.app_public_ip]
}

resource "aws_route53_record" "www" {
  zone_id = var.zone_id
  name    = "www.lookddak.com"
  type    = "CNAME"
  ttl     = 300
  records = ["lookddak.com."]
}
