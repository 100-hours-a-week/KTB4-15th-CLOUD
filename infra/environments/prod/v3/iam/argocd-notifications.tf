# ---------------------------------------------------------------
# Argo CD Notifications Controller
# - 배포 실패 이벤트만 기존 중앙 Alert Queue에 전송한다.
# - Discord Webhook과 재시도/DLQ 처리는 기존 Alert Lambda가 담당한다.
# ---------------------------------------------------------------
data "aws_iam_policy_document" "argocd_notifications" {
  statement {
    sid = "SendDeploymentFailureAlert"
    actions = [
      "sqs:GetQueueUrl",
      "sqs:SendMessage",
    ]
    resources = [var.alert_queue_arn]
  }
}

resource "aws_iam_role_policy" "argocd_notifications" {
  name   = "argocd-notifications-alert-queue"
  role   = aws_iam_role.irsa["argocd_notifications"].id
  policy = data.aws_iam_policy_document.argocd_notifications.json
}
