variable "name_prefix" {
  description = "Prod V3 워크로드 IAM Role과 Policy 이름 접두사"
  type        = string
}

variable "oidc_provider_arn" {
  description = "Prod V3 EKS OIDC Provider ARN"
  type        = string
}

variable "oidc_issuer" {
  description = "https://를 제외한 Prod V3 EKS OIDC Issuer"
  type        = string
}

variable "images_bucket_name" {
  description = "V1·V2와 공유하는 Prod 이미지 S3 Bucket 이름"
  type        = string
}

variable "sqs_queue_arns" {
  description = "V2·V3가 공유하는 Prod 피팅 Main Queue ARN"
  type        = map(string)

  validation {
    condition = alltrue([
      for name in ["be-fitting-request", "ai-fitting-response", "be-fitting-response"] :
      contains(keys(var.sqs_queue_arns), name)
    ])
    error_message = "Prod 피팅 Main Queue 3개의 ARN이 모두 필요합니다."
  }
}

variable "sqs_queue_urls" {
  description = "V2·V3가 공유하는 Prod 피팅 Main Queue URL"
  type        = map(string)

  validation {
    condition = alltrue([
      for name in ["be-fitting-request", "ai-fitting-response", "be-fitting-response"] :
      contains(keys(var.sqs_queue_urls), name)
    ])
    error_message = "Prod 피팅 Main Queue 3개의 URL이 모두 필요합니다."
  }
}
