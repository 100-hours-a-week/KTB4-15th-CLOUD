variable "name_prefix" {
  description = "V3 Dev 워크로드 IAM Role과 Policy 이름 접두사"
  type        = string
}

variable "oidc_provider_arn" {
  description = "V3 Dev EKS OIDC Provider ARN"
  type        = string
}

variable "oidc_issuer" {
  description = "https://를 제외한 V3 Dev EKS OIDC Issuer"
  type        = string
}

variable "images_bucket_name" {
  description = "전신 이미지와 가상 피팅 결과를 저장하는 Dev S3 Bucket 이름"
  type        = string
}

variable "sqs_queue_arns" {
  description = "V3 Dev 피팅 Main Queue ARN"
  type        = map(string)

  validation {
    condition = alltrue([
      for name in ["be-fitting-request", "ai-fitting-response", "be-fitting-response"] :
      contains(keys(var.sqs_queue_arns), name)
    ])
    error_message = "V3 Dev 피팅 Main Queue 3개의 ARN이 모두 필요합니다."
  }
}
