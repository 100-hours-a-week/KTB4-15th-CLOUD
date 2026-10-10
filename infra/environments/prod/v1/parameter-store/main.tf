resource "aws_ssm_parameter" "postgresql_database" {
  name        = "/lookddak/prod/postgresql/database"
  description = "Database name for EC2 PostgreSQL"
  type        = "String"
  value       = "lookddak_ai"
  tier        = "Standard"
  data_type   = "text"

  tags = {
    Environment = "prod"
    Service     = "postgresql"
  }

  lifecycle {
    ignore_changes = [tags, tags_all]
  }
}

resource "aws_ssm_parameter" "postgresql_username" {
  name        = "/lookddak/prod/postgresql/username"
  description = "Application username for EC2 PostgreSQL"
  type        = "String"
  value       = "lookddak_ai_app"
  tier        = "Standard"
  data_type   = "text"

  tags = {
    Environment = "prod"
    Service     = "postgresql"
  }

  lifecycle {
    ignore_changes = [tags, tags_all]
  }
}
