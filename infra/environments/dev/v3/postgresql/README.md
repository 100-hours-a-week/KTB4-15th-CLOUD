# V3 Dev PostgreSQL

V3는 V2와 같은 Dev PostgreSQL RDS의 `lookddak` Database를 사용한다 (2026-11-12, prod와 같은 구조). V3 Role은 V2 Role을 상속한다.

```text
공유 Dev PostgreSQL RDS
└─ lookddak   / lookddak_app ← lookddak_v3_app · lookddak_migration ← lookddak_v3_migration
```

## Terraform 적용 범위

- `/lookddak/dev/v3/postgresql` 아래의 비민감 연결정보 Parameter 생성
- V3 SecureString과 Database·사용자를 준비하는 SSM Runbook 생성
- DB Access Node에 Runbook 실행용 최소 Parameter Store·KMS 권한 부여
- V3 App·Migration 사용자와 `langgraph` Schema의 최소 권한 구성
- AI 상품 임베딩 Schema가 요구하는 `vector` Extension 준비
- GitOps 전환 동안 기존 Pod가 유지되도록 대상 IRSA에 V2·V3 Parameter를 함께 허용

비밀번호와 비밀번호가 포함된 DSN은 Terraform 코드, 변수, 출력, Plan과 State에 저장하지 않는다.

## 최초 구성 순서

1. Terraform을 적용한다.
2. `terraform output -raw dev_v3_postgresql_bootstrap_command`로 명령을 확인한다.
3. 출력된 명령을 실행해 SSM Command ID를 받는다.
4. 다음 명령으로 성공 여부를 확인한다.

```bash
aws ssm list-command-invocations \
  --region ap-northeast-2 \
  --command-id <Command ID> \
  --details
```

Runbook은 다음 작업을 멱등하게 수행한다.

- `lookddak_v3` Database 생성
- `lookddak_v3_app`, `lookddak_v3_migration` Role 생성
- 기존 SecureString 비밀번호가 유효하면 재사용하고, 없거나 불일치하면 DB Role과 동기화
- App·Migration 비밀번호와 App DSN을 SecureString으로 저장
- `public`, `langgraph` Schema와 역할별 최소 권한 구성
- 두 사용자로 TLS 연결 검증

## 후속 Migration

이 Runbook은 Database와 권한 기반만 구성하며 AI·Crawler 테이블을 생성하지 않는다.
AI와 Crawler 저장소의 SQL Migration을 V3 Migration 사용자로 적용하고, 필요한 상품 기준 데이터를 이관한 뒤 GitOps Parameter 경로를 변경한다.

## 주의사항

- V2 Database와 V2 Role의 권한·데이터는 변경하지 않는다.
- PostgreSQL의 `log_statement=all` 환경에서도 비밀번호가 RDS 로그에 남지 않도록 비밀번호 설정 세션은 statement logging을 비활성화한다.
- V3 EKS의 5432 접근 SG Rule은 `dev/v3/postgresql-access`에서 별도로 관리한다.
- GitOps 전환과 기능 검증이 끝나면 워크로드 IRSA의 V2 PostgreSQL Parameter 권한을 제거한다.
