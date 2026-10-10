# ---------------------------------------------------------------
# Discord 알림 Lambda
# - 소스 코드: lambda/discord_alert/ (Terraform이 zip으로 묶어 배포)
# - 환경 변수에 Discord Webhook URL(비밀값)이 있으므로 코드에 적지 않고 무시한다
#   (값은 콘솔에서 관리, 저장소가 public이므로 절대 코드에 넣지 않는다)
# ---------------------------------------------------------------
data "archive_file" "discord_alert" {
  type        = "zip"
  source_dir  = "${path.module}/lambda/discord_alert"
  output_path = "${path.module}/.build/discord_alert.zip"
}

resource "aws_lambda_function" "discord_alert" {
  function_name = "lookddak-discord-alert"
  role          = var.discord_alert_role_arn
  runtime       = "python3.14"
  handler       = "lambda_function.lambda_handler"
  architectures = ["x86_64"]
  memory_size   = 128
  timeout       = 3

  filename         = data.archive_file.discord_alert.output_path
  source_code_hash = data.archive_file.discord_alert.output_base64sha256

  depends_on = [aws_cloudwatch_log_group.discord_alert]

  lifecycle {
    ignore_changes = [environment]
  }
}

# alert-queue의 메시지를 10개씩(최대 5초 대기) 묶어서 Lambda를 호출한다
resource "aws_lambda_event_source_mapping" "alert_queue" {
  event_source_arn                   = aws_sqs_queue.alert.arn
  function_name                      = aws_lambda_function.discord_alert.arn
  batch_size                         = 10
  maximum_batching_window_in_seconds = 5
  function_response_types            = ["ReportBatchItemFailures"]
  enabled                            = true
}
