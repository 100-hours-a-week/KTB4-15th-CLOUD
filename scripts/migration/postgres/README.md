# PostgreSQL 마이그레이션

이 디렉터리는 PostgreSQL 마이그레이션만 관리한다. MySQL 마이그레이션 파일은 이 경로에 두지 않는다.

```text
postgres/
├── rehearsal/   # Dev 환경 리허설
└── production/  # V1 Prod EC2에서 V2 Prod RDS로 실제 전환
```

두 환경은 각각 `ec2-runtime`, `automation`, `workload`, `sql`로 역할을 나눈다.
리허설의 이전 버전은 `rehearsal/legacy`에 보존하며 실제 실행 대상으로 사용하지 않는다.
