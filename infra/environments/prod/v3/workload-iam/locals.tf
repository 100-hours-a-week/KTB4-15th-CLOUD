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

  runtime_parameters = merge(
    {
      "s3/images/bucket" = var.images_bucket_name
    },
    {
      for name, url in var.sqs_queue_urls : "sqs/${name}/url" => url
    },
  )

  runtime_parameter_names = {
    for key in keys(local.runtime_parameters) : key => "/lookddak/prod/v3/${key}"
  }

  common_tags = {
    Component   = "workload-iam"
    Environment = "prod"
    Version     = "v3"
  }

  workloads = {
    identity-api = {
      namespace       = "lookddak-identity"
      service_account = "identity-api"
      parameter_names = [
        "/lookddak/prod/v3/mysql/jdbc-url",
        "/lookddak/prod/v3/mysql/app/username",
        "/lookddak/prod/v3/mysql/app/password",
        "/lookddak/prod/spring/jwt-secret",
        "/lookddak/prod/internal/ai-api-key",
        local.runtime_parameter_names["s3/images/bucket"],
      ]
    }
    body-image-validator = {
      namespace       = "lookddak-identity"
      service_account = "body-image-validator"
      parameter_names = [
        "/lookddak/prod/internal/ai-api-key",
        "/lookddak/prod/fastapi/body-image-validation/url",
        "/lookddak/prod/fastapi/body-image-validation/proxy-key",
        "/lookddak/prod/fastapi/body-image-validation/proxy-secret",
        "/lookddak/prod/fastapi/body-image-validation/api-key",
        "/lookddak/prod/fastapi/runware-vton-api-key",
        "/lookddak/prod/fastapi/runware-llm-api-key",
        local.runtime_parameter_names["s3/images/bucket"],
      ]
    }
    commerce-api = {
      namespace       = "lookddak-commerce"
      service_account = "commerce-api"
      parameter_names = [
        "/lookddak/prod/v3/mysql/jdbc-url",
        "/lookddak/prod/v3/mysql/app/username",
        "/lookddak/prod/v3/mysql/app/password",
        "/lookddak/prod/spring/jwt-secret",
        "/lookddak/prod/spring/internal-api-key",
      ]
    }
    price-crawler = {
      namespace       = "lookddak-commerce"
      service_account = "price-crawler"
      parameter_names = [
        "/lookddak/prod/v3/postgresql/app/database-url",
        "/lookddak/prod/internal/price-refresh-backend-auth-headers",
      ]
    }
    chat-api = {
      namespace       = "lookddak-chat"
      service_account = "chat-api"
      parameter_names = [
        "/lookddak/prod/v3/mysql/jdbc-url",
        "/lookddak/prod/v3/mysql/app/username",
        "/lookddak/prod/v3/mysql/app/password",
        "/lookddak/prod/spring/jwt-secret",
        "/lookddak/prod/internal/ai-api-key",
      ]
    }
    chat-ai = {
      namespace       = "lookddak-chat"
      service_account = "chat-ai"
      parameter_names = [
        "/lookddak/prod/v3/postgresql/app/database-url",
        "/lookddak/prod/v3/postgresql/app/checkpoint-dsn",
        "/lookddak/prod/internal/ai-api-key",
        "/lookddak/prod/fastapi/runware-llm-api-key",
        "/lookddak/prod/fastapi/runware-vton-api-key",
        "/lookddak/prod/fastapi/openAI-api-key",
      ]
    }
    fitting-api = {
      namespace       = "lookddak-fitting"
      service_account = "fitting-api"
      parameter_names = [
        "/lookddak/prod/v3/mysql/jdbc-url",
        "/lookddak/prod/v3/mysql/app/username",
        "/lookddak/prod/v3/mysql/app/password",
        "/lookddak/prod/spring/jwt-secret",
        "/lookddak/prod/internal/ai-api-key",
        local.runtime_parameter_names["s3/images/bucket"],
      ]
    }
    fitting-worker = {
      namespace       = "lookddak-fitting"
      service_account = "fitting-worker"
      parameter_names = [
        "/lookddak/prod/v3/mysql/jdbc-url",
        "/lookddak/prod/v3/mysql/app/username",
        "/lookddak/prod/v3/mysql/app/password",
        "/lookddak/prod/spring/jwt-secret",
        local.runtime_parameter_names["sqs/be-fitting-request/url"],
        local.runtime_parameter_names["sqs/be-fitting-response/url"],
      ]
    }
    vton-orchestrator = {
      namespace       = "lookddak-fitting"
      service_account = "vton-orchestrator"
      parameter_names = [
        "/lookddak/prod/v3/postgresql/app/database-url",
        "/lookddak/prod/internal/ai-api-key",
        "/lookddak/prod/fastapi/runware-vton-api-key",
        "/lookddak/prod/fastapi/runware-llm-api-key",
        "/lookddak/prod/fastapi/webhook-token",
        "/lookddak/prod/fastapi/virtual-fitting-runware-webhook-url",
        local.runtime_parameter_names["s3/images/bucket"],
        local.runtime_parameter_names["sqs/be-fitting-request/url"],
        local.runtime_parameter_names["sqs/ai-fitting-response/url"],
        local.runtime_parameter_names["sqs/be-fitting-response/url"],
      ]
    }
  }
}
