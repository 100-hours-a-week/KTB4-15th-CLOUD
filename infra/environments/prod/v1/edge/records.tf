# ---------------------------------------------------------------
# V1 서비스 주소 레코드
# - lookddak.com(apex)은 V2 전환으로 prod/v2/edge(CloudFront alias)로 옮겼다.
# - www.lookddak.com은 lookddak.com CNAME이라 그대로 V2 CloudFront로 간다.
# ---------------------------------------------------------------
resource "aws_route53_record" "www" {
  zone_id = var.zone_id
  name    = "www.lookddak.com"
  type    = "CNAME"
  ttl     = 300
  records = ["lookddak.com."]
}
