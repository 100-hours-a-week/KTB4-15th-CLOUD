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
  }
}
