# ---------------------------------------------------------------
# V3 dev (EKS)
# - 기존 dev VPC를 쓰고, 새 리소스는 dev/v3에만 둔다 (V1/V2 파일과 충돌 방지).
# ---------------------------------------------------------------

module "dev_local_sqs" {
  source = "./dev/v3/local-sqs"

  local_test_user_name = module.dev_v2_iam.mq_local_test_user_name
}

output "dev_local_sqs_queue_urls" {
  description = "로컬 피팅 테스트 Main Queue URL"
  value       = module.dev_local_sqs.queue_urls
}

output "dev_local_sqs_queue_arns" {
  description = "로컬 피팅 테스트 Main Queue ARN"
  value       = module.dev_local_sqs.queue_arns
}

output "dev_local_sqs_dlq_urls" {
  description = "로컬 피팅 테스트 DLQ URL"
  value       = module.dev_local_sqs.dlq_urls
}

output "dev_local_sqs_dlq_arns" {
  description = "로컬 피팅 테스트 DLQ ARN"
  value       = module.dev_local_sqs.dlq_arns
}

output "dev_local_sqs_iam_policy_arn" {
  description = "공유 로컬 테스트 사용자에 연결한 Queue 최소 권한 Policy ARN"
  value       = module.dev_local_sqs.iam_policy_arn
}

removed {
  from = module.dev_v3_monitoring.aws_ecr_repository.db_log_tailer

  lifecycle {
    destroy = false
  }
}
