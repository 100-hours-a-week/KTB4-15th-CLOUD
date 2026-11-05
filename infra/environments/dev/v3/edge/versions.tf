terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      # CloudFront 뷰어 인증서는 us-east-1 ACM만 쓸 수 있다
      configuration_aliases = [
        aws.us_east_1,
      ]
    }
  }
}
