locals {
  prod_v3_quota_baselines = {
    ec2_standard_vcpu = {
      service_code = "ec2"
      quota_code   = "L-1216C47A"
      minimum      = 64
    }
    elastic_ip = {
      service_code = "ec2"
      quota_code   = "L-0263D0A3"
      minimum      = 5
    }
    network_interface = {
      service_code = "vpc"
      quota_code   = "L-DF5E4CA3"
      minimum      = 5000
    }
    ipv4_cidr_per_vpc = {
      service_code = "vpc"
      quota_code   = "L-83CA0A9D"
      minimum      = 2
    }
    application_load_balancer = {
      service_code = "elasticloadbalancing"
      quota_code   = "L-53DA6B97"
      minimum      = 5
    }
    network_load_balancer = {
      service_code = "elasticloadbalancing"
      quota_code   = "L-69A177A2"
      minimum      = 5
    }
  }
}

data "aws_servicequotas_service_quota" "prod_v3" {
  for_each = local.prod_v3_quota_baselines

  service_code = each.value.service_code
  quota_code   = each.value.quota_code
}

check "prod_v3_quota_baseline" {
  assert {
    condition = alltrue([
      for key, quota in local.prod_v3_quota_baselines :
      data.aws_servicequotas_service_quota.prod_v3[key].value >= quota.minimum
    ])
    error_message = "Prod V3 EKS 기본 용량에 필요한 EC2·EIP·ENI·VPC CIDR·LB Service Quota가 기준보다 낮습니다. CAPACITY.md를 확인하세요."
  }
}

output "prod_v3_service_quotas" {
  description = "Prod V3 EKS 구축 전 점검한 계정 Service Quota"
  value = {
    for key, quota in data.aws_servicequotas_service_quota.prod_v3 :
    key => quota.value
  }
}
