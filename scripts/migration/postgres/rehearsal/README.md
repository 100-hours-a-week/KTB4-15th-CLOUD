# PostgreSQL 마이그레이션 리허설

Dev EC2와 Dev V2 RDS 사이에서 논리 복제·PgBouncer 전환·롤백을 검증한 파일이다.

```text
rehearsal/
├── ec2-runtime/  # Dev EC2에 배치할 PgBouncer 설정
├── automation/   # 준비·복제·전환·복구 명령
├── workload/     # pgbench·k6 부하 파일
├── sql/          # 정합성·복제 상태 확인 SQL
└── legacy/       # 과거 리허설 이력, 실행 대상 아님
```

`rehersal` 오타 경로는 더 이상 사용하지 않는다.
