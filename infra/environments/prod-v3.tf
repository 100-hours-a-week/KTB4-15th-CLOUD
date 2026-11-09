# ---------------------------------------------------------------
# V3 prod (EKS)
# - 기존 Terraform Root·State·CI 경계를 그대로 사용한다.
# - 신규 리소스는 prod/v3 모듈에만 두고 기존 Prod V1/V2 리소스는
#   AWS Data Source로 조회하여 소유권과 State를 이동하지 않는다.
# ---------------------------------------------------------------
locals {
  prod_v3_cluster_name = "lookddak-prod"
}

data "aws_vpc" "prod_v3" {
  filter {
    name   = "tag:Name"
    values = ["lookddak-prod-vpc"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

data "aws_nat_gateway" "prod_v3" {
  vpc_id = data.aws_vpc.prod_v3.id
  state  = "available"

  filter {
    name   = "tag:Name"
    values = ["lookddak-prod-v2-nat"]
  }
}

data "aws_security_group" "prod_v3_api_access" {
  vpc_id = data.aws_vpc.prod_v3.id

  filter {
    name   = "tag:Name"
    values = ["lookddak-prod-monitoring-sg"]
  }
}

data "aws_instances" "prod_v3_api_access" {
  instance_state_names = ["running"]

  filter {
    name   = "tag:Name"
    values = ["lookddak-prod-monitoring"]
  }
}
