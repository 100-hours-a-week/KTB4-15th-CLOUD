# KTB4-15th-CLOUD

LookDDak 인프라를 Terraform으로 관리하는 저장소입니다.
**`main` 브랜치의 코드가 곧 실제 AWS 인프라의 상태**이며, 모든 변경은 PR → plan 리뷰 → merge → apply 순서로만 반영합니다.

## 목차

- [디렉토리 구조](#디렉토리-구조)
- [초기 세팅](#초기-세팅)
- [작업 방법](#작업-방법)
- [작업 규칙](#작업-규칙)
- [Terraform 외부에서 수동 관리하는 리소스](#terraform-외부에서-수동-관리하는-리소스)

---

## 디렉토리 구조

```
.
├── .github/workflows/
│   ├── terraform-pr.yaml       # PR: fmt, validate, tflint, plan → PR 코멘트
│   └── terraform-apply.yaml    # main merge: plan → apply
└── infra/
    ├── modules/                # 재사용 모듈 (2곳 이상에서 쓰는 것만)
    └── environments/           # ★ Terraform root: 여기서만 init/plan 실행
        ├── backend.tf          # S3 state 설정 (state 파일 1개)
        ├── providers.tf        # Terraform / AWS Provider 버전
        ├── main.tf             # 하위 폴더를 module로 호출
        ├── .tflint.hcl
        ├── .terraform.lock.hcl # Provider 버전 고정 (커밋 대상)
        ├── shared/core/        # 공용 리소스 (VPC, ALB, Route53, ECR ...)
        ├── prod/               # 운영 환경
        └── dev/                # 개발/스테이징 환경
```

- state는 S3의 **`terraform.tfstate` 하나**로 관리합니다.
- `environments/` 아래 하위 폴더에는 `backend`, `provider` 블록을 두지 않습니다. 모두 `environments/main.tf`에서 module로 호출됩니다.
- 하위 폴더 간 값 전달은 각 폴더의 `outputs.tf` → `main.tf` → `variables.tf`로 연결합니다.

---

## 초기 세팅

### 1. 도구 설치 (macOS)

```bash
brew install tfenv tflint awscli gh

# Terraform 버전은 CI와 동일하게 1.16.5로 고정
tfenv install 1.16.5
tfenv use 1.16.5

terraform -version   # Terraform v1.16.5
```

> `brew install terraform`으로 설치한 Terraform이 있다면 tfenv와 충돌하므로 `brew uninstall terraform` 후 진행하세요.

| 도구 | 버전 |
|---|---|
| Terraform CLI | `1.16.5` |
| AWS Provider | `~> 6.61` (`.terraform.lock.hcl`로 고정) |

### 2. AWS 자격 증명 설정

로컬에서는 **plan까지만** 실행하므로 읽기 권한이 있는 계정이면 충분합니다. Root 계정의 Access Key는 사용하지 마세요.

```bash
aws configure --profile lookddak
# Region: ap-northeast-2 / Output: json

export AWS_PROFILE=lookddak
aws sts get-caller-identity   # 계정 ID 686496667254 확인
```

### 3. 저장소 클론 및 초기화

```bash
git clone https://github.com/100-hours-a-week/KTB4-15th-CLOUD.git
cd KTB4-15th-CLOUD/infra/environments

terraform init
```

`Terraform has been successfully initialized!`가 출력되면 완료입니다.

### 4. 동작 확인

```bash
terraform plan -lock=false
```

`No changes. Your infrastructure matches the configuration.`가 나오면 로컬 코드와 실제 인프라가 일치하는 상태입니다.

> `-lock=false`: 로컬 plan이 CI의 apply와 state lock을 두고 충돌하지 않게 합니다.

### (선택) 에디터

- VS Code: **HashiCorp Terraform** 확장 설치 (저장 시 `terraform fmt` 자동 적용 권장)
- JetBrains: **Terraform and HCL** 플러그인

---

## 작업 방법

### 1. 이슈 생성 → 브랜치 생성

```bash
git checkout main
git pull
git checkout -b feature/<작업-내용>
```

### 2. 코드 작성 후 로컬 검증

```bash
cd infra/environments

terraform fmt -recursive ..    # 포맷 정리
terraform validate             # 문법 검사
tflint --init && tflint        # 린트
terraform plan -lock=false     # 변경 내용 확인 (apply는 하지 않음)
```

### 3. 커밋 → PR 생성

```bash
git add .
git commit -m "feat: <작업 내용>"
git push -u origin feature/<작업-내용>
gh pr create --base main
```

### 4. plan 리뷰

PR을 올리면 CI가 실행되고, plan 결과가 PR 코멘트로 달립니다. 리뷰 시 반드시 확인하세요.

| 기호 | 의미 | 주의 |
|---|---|---|
| `+` | 생성 | |
| `~` | 수정 (in-place) | |
| `-` | 삭제 | 의도한 삭제인지 확인 |
| `-/+` | **삭제 후 재생성** | **데이터 손실 가능. 특히 DB, S3는 절대 그냥 merge하지 말 것** |

### 5. merge → 자동 apply

merge하면 `terraform-apply` workflow가 실행되어 인프라에 반영됩니다. Actions 탭에서 성공 여부를 확인하세요.

---

## 작업 규칙

- **Terraform으로 관리하는 리소스는 콘솔에서 직접 수정하지 않습니다.** 다음 apply 때 코드 상태로 되돌아갑니다.
- **로컬에서 `terraform apply`를 실행하지 않습니다.** apply는 CI에서만 실행합니다.
- 리소스 삭제는 **해당 리소스 코드를 지우는 PR**로 합니다. `backend.tf`, `providers.tf`는 지우지 않습니다.
- 비밀번호, API 키 등 민감 정보는 코드에 직접 쓰지 않습니다. (Secrets Manager / GitHub Secrets 사용)
- 리소스 이름 규칙: `{project}-{environment}-{service}-{resource}` (예: `lookddak-prod-api-alb`)

### Git에 올리지 않는 파일

`.gitignore`로 제외되어 있습니다: `.terraform/`, `*.tfstate*`, `tfplan`, `plan.txt`, `*.tfvars`

`.terraform.lock.hcl`은 **커밋합니다.**

---

## Terraform 외부에서 수동 관리하는 리소스

아래 리소스는 Terraform 실행 전제 조건이므로 콘솔에서 직접 관리합니다. Terraform 코드에 추가하지 마세요.

| 리소스 | 이름 | 사용처 |
|---|---|---|
| State S3 버킷 | `lookddak-terraform-state-686496667254` | Terraform state 저장 (버전 관리 활성화) |
| GitHub OIDC Provider | `token.actions.githubusercontent.com` | GitHub Actions → AWS 인증 |
| Plan Role | `gha-terraform-plan-role` | PR 워크플로 (`terraform-pr`) |
| Apply Role | `gha-terraform-apply-role` | main 워크플로 (`terraform-apply`) |