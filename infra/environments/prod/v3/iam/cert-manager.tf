# ---------------------------------------------------------------
# cert-manager (Let's Encrypt DNS-01, Route53)
# - Istio Gateway에서 TLS를 종료하므로 CloudFront가 검증할 공인 인증서가 클러스터 안에 필요하다.
# - cert-manager가 _acme-challenge TXT 레코드를 만들고 지워 도메인 소유를 증명한다.
# - 권한 범위: lookddak.com Hosted Zone의 _acme-challenge.* TXT 레코드만 변경 (cert-manager 공식 Route53 문서 기준)
# ---------------------------------------------------------------
data "aws_iam_policy_document" "cert_manager" {
  statement {
    sid       = "GetChange"
    actions   = ["route53:GetChange"]
    resources = ["arn:aws:route53:::change/*"]
  }

  statement {
    sid       = "ChangeAcmeChallengeRecords"
    actions   = ["route53:ChangeResourceRecordSets"]
    resources = ["arn:aws:route53:::hostedzone/${var.route53_zone_id}"]

    condition {
      test     = "ForAllValues:StringEquals"
      variable = "route53:ChangeResourceRecordSetsRecordTypes"
      values   = ["TXT"]
    }

    condition {
      test     = "ForAllValues:StringLike"
      variable = "route53:ChangeResourceRecordSetsNormalizedRecordNames"
      values   = ["_acme-challenge.*"]
    }
  }

  statement {
    sid       = "ListRecords"
    actions   = ["route53:ListResourceRecordSets"]
    resources = ["arn:aws:route53:::hostedzone/${var.route53_zone_id}"]
  }

  statement {
    sid       = "ListHostedZones"
    actions   = ["route53:ListHostedZonesByName"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "cert_manager" {
  name   = "cert-manager-route53-dns01"
  role   = aws_iam_role.irsa["cert_manager"].id
  policy = data.aws_iam_policy_document.cert_manager.json
}
