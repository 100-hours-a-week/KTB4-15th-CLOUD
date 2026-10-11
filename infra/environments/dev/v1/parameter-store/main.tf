# V1 dev EC2 PostgreSQL 접속 정보 (String). 비밀번호(SecureString)는 콘솔에서 관리한다.

resource "aws_ssm_parameter" "postgresql_database" {
  name        = "/lookddak/dev/postgresql/database"
  description = "Database name for dev EC2 PostgreSQL"
  type        = "String"
  value       = "lookddak_ai"
  tier        = "Standard"
  data_type   = "text"

  tags = {
    Environment = "dev"
    Service     = "postgresql"
  }
}

resource "aws_ssm_parameter" "postgresql_username" {
  name        = "/lookddak/dev/postgresql/username"
  description = "Application username for dev EC2 PostgreSQL"
  type        = "String"
  value       = "lookddak_ai_app"
  tier        = "Standard"
  data_type   = "text"

  tags = {
    Environment = "dev"
    Service     = "postgresql"
  }
}
