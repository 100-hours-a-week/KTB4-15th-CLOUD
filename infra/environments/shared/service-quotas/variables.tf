variable "ec2_ondemand_standard_vcpu" {
  description = "서울 리전 Running On-Demand Standard 인스턴스의 요청 vCPU 한도"
  type        = number

  validation {
    condition     = var.ec2_ondemand_standard_vcpu >= 32
    error_message = "EC2 On-Demand Standard vCPU 한도는 현재 값인 32 이상이어야 합니다."
  }
}
