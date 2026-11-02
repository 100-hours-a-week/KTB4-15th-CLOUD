terraform {
  required_version = "~> 1.16.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.61"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.7"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.3"
    }
  }
}

provider "aws" {
  region = "ap-northeast-2"

  default_tags {
    tags = {
      Project   = "lookddak"
      ManagedBy = "terraform"
    }
  }
}

# CloudFront viewer certificates must be created in us-east-1.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = {
      Project   = "lookddak"
      ManagedBy = "terraform"
    }
  }
}

# ---------------------------------------------------------------
# V3 dev EKS (lookddak-dev) 클러스터 안 설치용
# - 인증: aws eks get-token (CI apply Role = 관리자, CI plan Role = 조회 Access Entry)
# ---------------------------------------------------------------
provider "helm" {
  kubernetes = {
    host                   = module.dev_v3_eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.dev_v3_eks.cluster_certificate_authority_data)

    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.dev_v3_eks.cluster_name, "--region", "ap-northeast-2"]
    }
  }
}
