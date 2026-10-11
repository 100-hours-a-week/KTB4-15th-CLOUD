# ARN에 들어가는 계정 ID와 리전을 하드코딩하지 않고 현재 자격 증명·provider 설정에서 읽는다.
data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.region
}
