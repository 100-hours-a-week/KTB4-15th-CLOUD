# KTB4-15th-CLOUD

## Terraform 외부에서 수동 관리하는 리소스

아래 리소스는 Terraform 실행 전제 조건이므로 콘솔에서 직접 관리합니다. Terraform 코드에 추가하지 마세요.

| 리소스 | 이름 |
|---|---|
| State S3 버킷 | `lookddak-terraform-state-686496667254` |
| GitHub OIDC Provider | `token.actions.githubusercontent.com` |
| Plan Role (PR, 읽기 전용) | `gha-terraform-plan` |
| Apply Role (main, Admin) | `gha-terraform-apply` |