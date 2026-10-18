# V1 Prod PostgreSQL 마이그레이션

V1 Prod EC2 PostgreSQL에서 V2 Prod RDS PostgreSQL로 전환하기 위한 운영 원본이다.
민감정보는 실행 시 `/lookddak/prod/v2/postgresql/...` Parameter Store에서 조회한다.

```text
production/
├── ec2-runtime/  # /opt/lookddak 루트에 배치할 Compose·PgBouncer 설정
├── automation/   # 운영자가 실행할 준비·PgBouncer 활성화·복제·전환·복구 명령
├── workload/     # pgbench 부하 파일
├── sql/          # 계정·테이블·정합성 SQL
└── results/      # 실행 결과, Git 제외
```

서버 배치 경로는 다음과 같다.

```text
/opt/lookddak/
├── docker-compose.postgres-migration.yaml
├── pgbouncer.prod/
└── scripts/migration/postgres/production/
    ├── automation/
    ├── workload/
    ├── sql/
    └── results/
```

파일 배치만으로 서비스는 변경되지 않는다. 상태를 변경하는 명령은 `check`와 `run`을 분리하고,
실행 로그는 `results/<작업 ID>/`에 저장한다.

PgBouncer 런타임 파일을 준비한 뒤 FastAPI를 기존 EC2 PostgreSQL의 PgBouncer 경유로
전환할 때는 다음 명령을 사용한다. PostgreSQL과 pgbench는 기동하거나 재시작하지 않는다.

```bash
sudo POSTGRES_BIND_IP=10.20.1.203 \
  /opt/lookddak/scripts/migration/postgres/production/automation/activate-pgbouncer.sh \
  <작업-ID>
```

전환 중 검증에 실패하면 `.env`와 FastAPI를 기존 PostgreSQL 직결 상태로 자동 복구한다.

V1의 운영 스키마를 V2 RDS에 데이터 없이 준비하고 공통 계정 권한을 적용할 때는
다음 순서로 실행한다. `products_backup_*` 테이블은 제외하며 논리 복제는 시작하지 않는다.

```bash
sudo /opt/lookddak/scripts/migration/postgres/production/automation/prepare-rds-schema.py check
sudo /opt/lookddak/scripts/migration/postgres/production/automation/prepare-rds-schema.py apply
sudo /opt/lookddak/scripts/migration/postgres/production/automation/prepare-rds-schema.py verify
```
