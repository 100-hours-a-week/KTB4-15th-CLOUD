# ---------------------------------------------------------------
# Hosted Zone (도메인 등록 시 Route53이 자동 생성)
# NS, SOA 레코드는 Zone과 함께 AWS가 관리하므로 별도로 작성하지 않는다.
# ---------------------------------------------------------------
resource "aws_route53_zone" "main" {
  name    = "lookddak.com"
  comment = "HostedZone created by Route53 Registrar"
}

# ---------------------------------------------------------------
# 메일 (ImprovMX) - 서비스 버전과 무관하게 유지되는 레코드
# 서비스 주소 레코드(A, www)는 prod/v1/edge에서 관리한다.
# ---------------------------------------------------------------
resource "aws_route53_record" "mx" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "lookddak.com"
  type    = "MX"
  ttl     = 300
  records = [
    "10 mx1.improvmx.com",
    "20 mx2.improvmx.com",
  ]
}

resource "aws_route53_record" "spf" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "lookddak.com"
  type    = "TXT"
  ttl     = 300
  records = ["v=spf1 include:spf.improvmx.com ~all"]
}
