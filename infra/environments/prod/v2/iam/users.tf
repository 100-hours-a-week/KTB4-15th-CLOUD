resource "aws_iam_user" "modal_body_image_worker" {
  name = "lookddak-prod-modal-body-image-worker"

  tags = {
    Component   = "body-image-validation"
    Environment = "prod"
    Service     = "modal"
    Version     = "v2"
  }
}
