# ---------------------------------------------------------------
# Shared local MQ test user for BE and AI developers
# - Access keys are intentionally created outside Terraform so secrets are not
#   stored in Terraform state.
# ---------------------------------------------------------------
resource "aws_iam_user" "mq_local_test" {
  name          = "lookddak-dev-v2-mq-local-test"
  force_destroy = false

  tags = {
    Component   = "sqs"
    Environment = "dev"
    Purpose     = "local-mq-test"
    Version     = "v2"
  }
}
