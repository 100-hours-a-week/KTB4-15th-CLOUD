resource "aws_ssm_parameter" "rds_admin_username" {
  name        = "/lookddak/prod/rds/admin/username"
  description = "LookDDak production RDS administrator username"
  type        = "String"
  value       = var.rds_admin_username
  tier        = "Standard"
  data_type   = "text"

  tags = {
    CredentialType = "admin"
    Environment    = "prod"
    Service        = "rds"
  }

  lifecycle {
    ignore_changes = [tags, tags_all]
  }
}

resource "aws_ssm_parameter" "rds_app_username" {
  name        = "/lookddak/prod/rds/app/username"
  description = "LookDDak production Spring Boot DB username"
  type        = "String"
  value       = "lookddak_app"
  tier        = "Standard"
  data_type   = "text"

  tags = {
    CredentialType = "app"
    Environment    = "prod"
    Service        = "rds"
  }

  lifecycle {
    ignore_changes = [tags, tags_all]
  }
}

resource "aws_ssm_parameter" "rds_database" {
  name        = "/lookddak/prod/rds/database"
  description = "LookDDak production RDS database name"
  type        = "String"
  value       = var.rds_database
  tier        = "Standard"
  data_type   = "text"

  tags = {
    Environment = "prod"
    Service     = "rds"
  }

  lifecycle {
    ignore_changes = [tags, tags_all]
  }
}

resource "aws_ssm_parameter" "rds_host" {
  name        = "/lookddak/prod/rds/host"
  description = "LookDDak production RDS endpoint"
  type        = "String"
  value       = var.rds_host
  tier        = "Standard"
  data_type   = "text"

  tags = {
    Environment = "prod"
    Service     = "rds"
  }

  lifecycle {
    ignore_changes = [tags, tags_all]
  }
}

resource "aws_ssm_parameter" "rds_port" {
  name        = "/lookddak/prod/rds/port"
  description = "LookDDak production RDS port"
  type        = "String"
  value       = tostring(var.rds_port)
  tier        = "Standard"
  data_type   = "text"

  tags = {
    Environment = "prod"
    Service     = "rds"
  }

  lifecycle {
    ignore_changes = [tags, tags_all]
  }
}
