# tflint 설정 (infra/environments에서 실행)
plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

# AWS 전용 규칙 (잘못된 인스턴스 타입 등)
# 버전: https://github.com/terraform-linters/tflint-ruleset-aws/releases
plugin "aws" {
  enabled = true
  version = "0.49.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}
