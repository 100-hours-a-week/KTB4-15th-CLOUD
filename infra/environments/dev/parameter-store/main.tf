# dev RDS 접속 정보 (String). 비밀번호(SecureString)는 콘솔에서 관리한다.

resource "aws_ssm_parameter" "rds_admin_username" {
  name        = "/lookddak/dev/rds/admin/username"
  description = "LookDDak dev RDS administrator username"
  type        = "String"
  value       = var.rds_admin_username
  tier        = "Standard"
  data_type   = "text"

  tags = {
    CredentialType = "admin"
    Environment    = "dev"
    Service        = "rds"
  }
}

resource "aws_ssm_parameter" "rds_app_username" {
  name        = "/lookddak/dev/rds/app/username"
  description = "LookDDak dev Spring Boot DB username"
  type        = "String"
  value       = "lookddak_app"
  tier        = "Standard"
  data_type   = "text"

  tags = {
    CredentialType = "app"
    Environment    = "dev"
    Service        = "rds"
  }
}

resource "aws_ssm_parameter" "rds_database" {
  name        = "/lookddak/dev/rds/database"
  description = "LookDDak dev RDS database name"
  type        = "String"
  value       = var.rds_database
  tier        = "Standard"
  data_type   = "text"

  tags = {
    Environment = "dev"
    Service     = "rds"
  }
}

resource "aws_ssm_parameter" "rds_host" {
  name        = "/lookddak/dev/rds/host"
  description = "LookDDak dev RDS endpoint"
  type        = "String"
  value       = var.rds_host
  tier        = "Standard"
  data_type   = "text"

  tags = {
    Environment = "dev"
    Service     = "rds"
  }
}

resource "aws_ssm_parameter" "rds_port" {
  name        = "/lookddak/dev/rds/port"
  description = "LookDDak dev RDS port"
  type        = "String"
  value       = tostring(var.rds_port)
  tier        = "Standard"
  data_type   = "text"

  tags = {
    Environment = "dev"
    Service     = "rds"
  }
}
