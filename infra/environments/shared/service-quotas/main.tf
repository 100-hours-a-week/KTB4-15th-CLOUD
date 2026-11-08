# ---------------------------------------------------------------
# 서울 리전 계정 공용 Service Quotas
# - EKS뿐 아니라 같은 계정과 리전의 Standard 계열 On-Demand EC2가 공유한다.
# - Quota 증가는 Terraform apply 시 AWS에 요청되며, 실제 반영에는 AWS 승인이 필요하다.
# ---------------------------------------------------------------
resource "aws_servicequotas_service_quota" "ec2_ondemand_standard_vcpu" {
  service_code = "ec2"
  quota_code   = "L-1216C47A"
  value        = var.ec2_ondemand_standard_vcpu
}
