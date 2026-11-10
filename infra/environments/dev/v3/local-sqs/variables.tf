variable "local_test_user_name" {
  description = "기존 BE·AI 공유 로컬 MQ 테스트 IAM User 이름"
  type        = string

  validation {
    condition     = var.local_test_user_name == "lookddak-dev-v2-mq-local-test"
    error_message = "검증된 공유 로컬 MQ 테스트 IAM User만 사용할 수 있습니다."
  }
}
