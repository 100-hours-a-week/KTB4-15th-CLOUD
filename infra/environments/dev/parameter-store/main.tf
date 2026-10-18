# dev RDS 접속 정보 (String). 비밀번호(SecureString)는 콘솔에서 관리한다.

locals {
  # Parameter Store는 값 없는 파라미터를 생성할 수 없으므로, 실제
  # SecureString은 AWS Console에서 수동 생성하고 Terraform에는 경로만 정의한다.
  fastapi_body_image_validation_parameter_paths = {
    BODY_IMAGE_VALIDATION_URL          = "/lookddak/dev/fastapi/body-image-validation/url"
    BODY_IMAGE_VALIDATION_PROXY_KEY    = "/lookddak/dev/fastapi/body-image-validation/proxy-key"
    BODY_IMAGE_VALIDATION_PROXY_SECRET = "/lookddak/dev/fastapi/body-image-validation/proxy-secret"
    BODY_IMAGE_VALIDATION_API_KEY      = "/lookddak/dev/fastapi/body-image-validation/api-key"
  }
}

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

# V2 dev Spring(ECS)이 V1 dev 구 DB에 연결할 때 쓰는 JDBC URL.
# V1 EC2는 host/port/database로 직접 조합하므로 이 값을 쓰지 않는다.
# 경로를 rds/app/ 아래에 둬서 V2 Task Execution Role의 기존 읽기 권한으로 읽힌다.
resource "aws_ssm_parameter" "rds_app_jdbc_url" {
  name        = "/lookddak/dev/rds/app/jdbc-url"
  description = "LookDDak dev Spring JDBC URL for the V1 dev MySQL instance"
  type        = "String"
  value       = "jdbc:mysql://${var.rds_host}:${var.rds_port}/${var.rds_database}?sslMode=REQUIRED&serverTimezone=UTC&characterEncoding=UTF-8"
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
