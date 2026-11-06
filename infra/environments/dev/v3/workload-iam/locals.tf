data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

data "aws_partition" "current" {}

data "aws_kms_alias" "ssm" {
  name = "alias/aws/ssm"
}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition
  region     = data.aws_region.current.region

  ssm_parameter_arn_prefix = "arn:${local.partition}:ssm:${local.region}:${local.account_id}:parameter"
  images_bucket_arn        = "arn:${local.partition}:s3:::${var.images_bucket_name}"

  common_tags = {
    Component   = "workload-iam"
    Environment = "dev"
    Version     = "v3"
  }

  workloads = {
    identity-api = {
      namespace       = "lookddak-identity"
      service_account = "identity-api"
      parameter_names = [
        "/lookddak/dev/v3/mysql/jdbc-url",
        "/lookddak/dev/v3/mysql/app/username",
        "/lookddak/dev/v3/mysql/app/password",
        "/lookddak/dev/spring/jwt-secret",
        "/lookddak/dev/internal/ai-api-key",
      ]
    }
    body-image-validator = {
      namespace       = "lookddak-identity"
      service_account = "body-image-validator"
      parameter_names = [
        "/lookddak/dev/internal/ai-api-key",
        "/lookddak/dev/fastapi/body-image-validation/url",
        "/lookddak/dev/fastapi/body-image-validation/proxy-key",
        "/lookddak/dev/fastapi/body-image-validation/proxy-secret",
        "/lookddak/dev/fastapi/body-image-validation/api-key",
        "/lookddak/dev/fastapi/runware-vton-api-key",
        "/lookddak/dev/fastapi/runware-llm-api-key",
      ]
    }
    commerce-api = {
      namespace       = "lookddak-commerce"
      service_account = "commerce-api"
      parameter_names = [
        "/lookddak/dev/v3/mysql/jdbc-url",
        "/lookddak/dev/v3/mysql/app/username",
        "/lookddak/dev/v3/mysql/app/password",
        "/lookddak/dev/spring/jwt-secret",
        "/lookddak/dev/spring/internal-api-key",
      ]
    }
    price-crawler = {
      namespace       = "lookddak-commerce"
      service_account = "price-crawler"
      parameter_names = [
        "/lookddak/dev/v2/postgresql/app/database-url",
        "/lookddak/dev/internal/price-refresh-backend-auth-headers",
      ]
    }
    chat-api = {
      namespace       = "lookddak-chat"
      service_account = "chat-api"
      parameter_names = [
        "/lookddak/dev/v3/mysql/jdbc-url",
        "/lookddak/dev/v3/mysql/app/username",
        "/lookddak/dev/v3/mysql/app/password",
        "/lookddak/dev/spring/jwt-secret",
        "/lookddak/dev/internal/ai-api-key",
      ]
    }
    chat-ai = {
      namespace       = "lookddak-chat"
      service_account = "chat-ai"
      parameter_names = [
        "/lookddak/dev/v2/postgresql/app/database-url",
        "/lookddak/dev/v2/postgresql/app/checkpoint-dsn",
        "/lookddak/dev/internal/ai-api-key",
        "/lookddak/dev/fastapi/runware-llm-api-key",
        "/lookddak/dev/fastapi/runware-vton-api-key",
        "/lookddak/dev/fastapi/openAI-api-key",
      ]
    }
    fitting-api = {
      namespace       = "lookddak-fitting"
      service_account = "fitting-api"
      parameter_names = [
        "/lookddak/dev/v3/mysql/jdbc-url",
        "/lookddak/dev/v3/mysql/app/username",
        "/lookddak/dev/v3/mysql/app/password",
        "/lookddak/dev/spring/jwt-secret",
        "/lookddak/dev/internal/ai-api-key",
      ]
    }
    fitting-worker = {
      namespace       = "lookddak-fitting"
      service_account = "fitting-worker"
      parameter_names = [
        "/lookddak/dev/v3/mysql/jdbc-url",
        "/lookddak/dev/v3/mysql/app/username",
        "/lookddak/dev/v3/mysql/app/password",
        "/lookddak/dev/spring/jwt-secret",
      ]
    }
    vton-orchestrator = {
      namespace       = "lookddak-fitting"
      service_account = "vton-orchestrator"
      parameter_names = [
        "/lookddak/dev/v2/postgresql/app/database-url",
        "/lookddak/dev/internal/ai-api-key",
        "/lookddak/dev/fastapi/runware-vton-api-key",
        "/lookddak/dev/fastapi/runware-llm-api-key",
        "/lookddak/dev/fastapi/webhook-token",
        "/lookddak/dev/fastapi/virtual-fitting-runware-webhook-url",
      ]
    }
  }
}
