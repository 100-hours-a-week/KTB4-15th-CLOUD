data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

data "aws_partition" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition
  region     = data.aws_region.current.region

  namespace = "monitoring"

  common_tags = {
    Component   = "monitoring"
    Environment = "dev"
    Version     = "v3"
  }

  buckets = {
    loki  = "${var.name_prefix}-loki-${local.account_id}-${local.region}"
    tempo = "${var.name_prefix}-tempo-${local.account_id}-${local.region}"
  }

  irsa = {
    loki = {
      service_account = "loki"
    }
    tempo = {
      service_account = "tempo"
    }
    db-log-tailer = {
      service_account = "db-log-tailer"
    }
    alloy-cluster = {
      service_account = "alloy-cluster"
    }
    oauth2-proxy = {
      service_account = "oauth2-proxy"
    }
  }

  oauth2_proxy_parameters = {
    client_secret = "/lookddak/dev/v3/monitoring/oauth2-proxy/client-secret"
    cookie_secret = "/lookddak/dev/v3/monitoring/oauth2-proxy/cookie-secret"
  }

  ssm_parameter_arn_prefix = "arn:${local.partition}:ssm:${local.region}:${local.account_id}:parameter"

  mysql_exporter = {
    username           = "lookddak_v3_exporter"
    client_host        = "100.65.%"
    password_parameter = "/lookddak/dev/v3/monitoring/mysql-exporter/password"
  }

  postgres_exporter_password_parameter = "/lookddak/dev/monitoring/postgres-exporter/password"
}
