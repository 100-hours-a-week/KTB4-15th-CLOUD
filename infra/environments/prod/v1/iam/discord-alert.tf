# ---------------------------------------------------------------
# Discord 알림 Lambda 실행 Role
# - SQS 수신, Lambda 로그 쓰기, 상태 로그 읽기, Webhook URL(SSM) 읽기
# ---------------------------------------------------------------

resource "aws_iam_role" "discord_alert" {
  lifecycle {
    ignore_changes = [tags, tags_all]
  }

  assume_role_policy = jsonencode({
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
    Version = "2012-10-17"
  })
  name = "lookddak-discord-alert-role-pl51jpue"
  path = "/service-role/"
  tags = {}
}

resource "aws_iam_policy" "discord_alert_logs" {
  lifecycle {
    ignore_changes = [tags, tags_all]
  }

  name = "AWSLambdaBasicExecutionRole-95b4d8dc-ae9a-4906-bfae-0a3702a265cf"
  path = "/service-role/"
  policy = jsonencode({
    Statement = [{
      Action   = "logs:CreateLogGroup"
      Effect   = "Allow"
      Resource = "arn:aws:logs:${local.region}:${local.account_id}:*"
      }, {
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Effect   = "Allow"
      Resource = ["arn:aws:logs:${local.region}:${local.account_id}:log-group:/aws/lambda/lookddak-discord-alert:*"]
    }]
    Version = "2012-10-17"
  })
  tags = {}
}

resource "aws_iam_role_policy_attachment" "discord_alert_logs" {
  policy_arn = aws_iam_policy.discord_alert_logs.arn
  role       = aws_iam_role.discord_alert.name
}

resource "aws_iam_role_policy_attachment" "discord_alert_sqs" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaSQSQueueExecutionRole"
  role       = aws_iam_role.discord_alert.name
}

# Discord 알림 Lambda가 Parameter Store에서 Webhook URL(SecureString)을 읽는 권한
# - 복호화 키는 AWS 관리형 키(alias/aws/ssm)라 kms:Decrypt는 키 정책에서 허용됨
resource "aws_iam_role_policy" "discord_alert_ssm_read" {
  name = "lookddak-discord-alert-ssm-read"
  policy = jsonencode({
    Statement = [{
      Sid      = "ReadDiscordWebhookParameters"
      Action   = "ssm:GetParameter"
      Effect   = "Allow"
      Resource = "arn:aws:ssm:${local.region}:${local.account_id}:parameter/lookddak/prod/discord/*"
    }]
    Version = "2012-10-17"
  })
  role = aws_iam_role.discord_alert.name
}

resource "aws_iam_role_policy" "discord_alert_status_logs_read" {
  name = "LamdaRole"
  policy = jsonencode({
    Statement = [{
      Action   = "logs:GetLogEvents"
      Effect   = "Allow"
      Resource = "arn:aws:logs:${local.region}:${local.account_id}:log-group:/lookddak/prod/status:*"
    }]
    Version = "2012-10-17"
  })
  role = aws_iam_role.discord_alert.name
}
