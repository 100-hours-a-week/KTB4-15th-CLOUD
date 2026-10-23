# ---------------------------------------------------------------
# DB 쿼리 로그 수집 (db-log-tailer, Monitoring EC2 컨테이너)
# - RDS 로그 파일을 RDS API로 이어 읽어 Loki로 보낸다 (CloudWatch Logs를 거치지 않는다).
#   MySQL: MariaDB Audit Plugin 감사 로그, PostgreSQL: log_statement=all + log_duration
# - DB 쪽 설정은 dev/v2/database에 있다.
# ---------------------------------------------------------------
locals {
  db_query_log_instances = ["lookddak-dev-v2-mysql", "lookddak-dev-postgresql"]
}

resource "aws_iam_role_policy" "db_query_log" {
  name = "db-query-log-read"
  role = aws_iam_role.instance.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "ReadRdsLogFiles"
      Effect = "Allow"
      Action = [
        "rds:DescribeDBLogFiles",
        "rds:DownloadDBLogFilePortion",
      ]
      Resource = [
        for id in local.db_query_log_instances :
        "arn:${data.aws_partition.current.partition}:rds:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:db:${id}"
      ]
    }]
  })
}
