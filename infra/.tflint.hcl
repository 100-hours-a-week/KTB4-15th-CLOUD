# infra/.tflint.hcl
plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

# AWS 전용 규칙(잘못된 인스턴스 타입 등)도 쓰려면 아래 주석을 풀고
# https://github.com/terraform-linters/tflint-ruleset-aws/releases 의 최신 버전을 넣으세요.
plugin "aws" {
  enabled = true
  version = "0.49.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}
