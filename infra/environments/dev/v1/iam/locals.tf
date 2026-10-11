data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.region

  # dev 서버가 쓰는 리소스 (prod 리소스에는 접근 권한을 주지 않는다)
  image_bucket_arn = "arn:aws:s3:::lookddak-dev-images-${local.account_id}-${local.region}"
}
