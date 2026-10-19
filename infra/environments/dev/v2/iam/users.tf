# ---------------------------------------------------------------
# Shared local MQ test and application log viewer user for BE and AI developers
# - Access keys are intentionally created outside Terraform so secrets are not
#   stored in Terraform state.
# ---------------------------------------------------------------
resource "aws_iam_user" "mq_local_test" {
  name          = "lookddak-dev-v2-mq-local-test"
  force_destroy = false

  tags = {
    Component   = "sqs-cloudwatch-logs"
    Environment = "dev"
    Purpose     = "local-mq-test-and-log-view"
    Version     = "v2"
  }
}
