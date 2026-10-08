data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "pipeline_test" {
  bucket = "pipeline-test-${data.aws_caller_identity.current.account_id}"
}