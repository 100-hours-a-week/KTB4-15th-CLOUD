# V3 Dev MySQL 격리

V2와 V3는 같은 Dev MySQL RDS 인스턴스를 사용하지만 Database와 앱 사용자를 분리한다.

```text
공유 Dev MySQL RDS
├─ lookddak      / 기존 V2 사용자
└─ lookddak_v3   / lookddak_v3_app
```

## Terraform 적용 범위

- V3 EKS Cluster Security Group에서 MySQL 3306 접근 허용
- `/lookddak/dev/v3/mysql/jdbc-url` String Parameter 생성
- `/lookddak/dev/v3/mysql/app/username` String Parameter 생성
- V3 전용 SecureString과 Database·사용자를 준비하는 SSM Runbook 생성
- DB Access Node에 Runbook 실행용 최소 Parameter Store·KMS 권한 부여

비밀번호는 Terraform 코드, 변수, 출력, Plan과 State에 저장하지 않는다.

## 최초 구성 순서

1. Terraform을 적용한다.
2. `terraform output -raw dev_v3_mysql_bootstrap_command`로 명령을 확인한다.
3. 출력된 명령을 실행해 SSM Command ID를 받는다.
4. 다음 명령으로 성공 여부를 확인한다.

```bash
aws ssm list-command-invocations \
  --region ap-northeast-2 \
  --command-id <Command ID> \
  --details
```

Runbook은 다음 작업을 멱등하게 수행한다.

- `/lookddak/dev/v3/mysql/app/password`로 로그인이 안 되면 MySQL이 새 무작위 비밀번호를 생성해 SecureString으로 저장
- `lookddak_v3` Database 생성
- `lookddak_v3_app` 사용자 생성 또는 비밀번호 일치
- `lookddak_v3.*` 범위에만 권한 부여
- V3 사용자로 `SELECT 1` 연결 검증

## 주의사항

- 이 Runbook은 V2 Database나 V2 사용자의 권한을 변경하지 않는다.
- MySQL Audit Log에 비밀번호가 남지 않도록 SQL에는 `IDENTIFIED BY RANDOM PASSWORD`만 기록한다.
- Cilium의 워크로드 egress 허용은 네트워크 정책 작업에서 별도로 구성한다.
- GitOps 워크로드는 V3 Parameter 경로로 변경한 뒤 배포한다.
