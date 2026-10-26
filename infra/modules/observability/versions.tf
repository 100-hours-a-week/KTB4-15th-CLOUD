terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      # Grafana CloudFront 뷰어 인증서(us-east-1). grafana_cloudfront_enabled = true일 때만 쓴다
      configuration_aliases = [
        aws.us_east_1,
      ]
    }
    archive = {
      source = "hashicorp/archive"
    }
  }
}
