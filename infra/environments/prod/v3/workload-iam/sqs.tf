# fitting-worker는 DB Outbox 요청을 발행하고 완료 결과만 소비한다.
data "aws_iam_policy_document" "fitting_worker_sqs" {
  statement {
    sid       = "PublishFittingRequests"
    actions   = ["sqs:SendMessage"]
    resources = [var.sqs_queue_arns["be-fitting-request"]]
  }

  statement {
    sid = "ConsumeFittingResults"
    actions = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:ChangeMessageVisibility",
    ]
    resources = [var.sqs_queue_arns["be-fitting-response"]]
  }
}

resource "aws_iam_role_policy" "fitting_worker_sqs" {
  name   = "${var.name_prefix}-fitting-worker-sqs"
  role   = aws_iam_role.workload["fitting-worker"].id
  policy = data.aws_iam_policy_document.fitting_worker_sqs.json
}

# vton-orchestrator는 요청을 소비하고 AI 중간 결과와 BE 최종 결과를 전달한다.
data "aws_iam_policy_document" "vton_orchestrator_sqs" {
  statement {
    sid = "ConsumeFittingRequests"
    actions = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:ChangeMessageVisibility",
    ]
    resources = [var.sqs_queue_arns["be-fitting-request"]]
  }

  statement {
    sid = "ProduceAndConsumeAiResponses"
    actions = [
      "sqs:SendMessage",
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:ChangeMessageVisibility",
    ]
    resources = [var.sqs_queue_arns["ai-fitting-response"]]
  }

  statement {
    sid       = "PublishFittingResults"
    actions   = ["sqs:SendMessage"]
    resources = [var.sqs_queue_arns["be-fitting-response"]]
  }
}

resource "aws_iam_role_policy" "vton_orchestrator_sqs" {
  name   = "${var.name_prefix}-vton-orchestrator-sqs"
  role   = aws_iam_role.workload["vton-orchestrator"].id
  policy = data.aws_iam_policy_document.vton_orchestrator_sqs.json
}
