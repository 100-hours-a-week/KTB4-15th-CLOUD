# V1 Prod PostgreSQL 마이그레이션

V1 Prod EC2 PostgreSQL에서 V2 Prod RDS PostgreSQL로 전환하기 위한 운영 원본이다.
민감정보는 실행 시 `/lookddak/prod/v2/postgresql/...` Parameter Store에서 조회한다.

```text
production/
├── ec2-runtime/  # /opt/lookddak 루트에 배치할 Compose·PgBouncer 설정
├── automation/   # 운영자가 실행할 준비·PgBouncer 활성화·복제·전환·복구 명령
├── workload/     # pgbench 쓰기 검증 및 k6 읽기 연속성 검증
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

## k6 운영 읽기 검증

운영 전환 전부터 전환 후까지 `lookddak.com` 읽기 API를 10 RPS로 호출한다.
운영 데이터를 만들지 않으며 테스트 계정도 자동 생성하지 않는다.

먼저 기존 운영 테스트 계정의 Bearer Token 또는 Cookie 문자열만 들어 있는 파일을 EC2에 준비한다.
파일 내용은 로그와 Git에 남기지 않는다.

```bash
sudo install -o root -g root -m 0600 /dev/null /opt/lookddak/k6.prod.auth
sudoedit /opt/lookddak/k6.prod.auth
```

기본 인증 방식은 Cookie이다. Bearer Token 파일이라면 각 명령에 `K6_AUTH_KIND=bearer`를 지정한다.

```bash
RUN_ID="prod-pg-cutover-$(date -u +%Y%m%dT%H%M%SZ)"

sudo /opt/lookddak/scripts/migration/postgres/production/automation/k6-read-control.sh prepare "$RUN_ID"
sudo /opt/lookddak/scripts/migration/postgres/production/automation/k6-read-control.sh check "$RUN_ID"
sudo /opt/lookddak/scripts/migration/postgres/production/automation/k6-read-control.sh start "$RUN_ID"
sudo /opt/lookddak/scripts/migration/postgres/production/automation/k6-read-control.sh status "$RUN_ID"
sudo /opt/lookddak/scripts/migration/postgres/production/automation/k6-read-control.sh finish "$RUN_ID"
```

기본값은 다음과 같다.

- 대상: `https://lookddak.com/api/v1/chat-rooms`
- 부하: 초당 10회
- 실행 시간: 10분
- 합격 기준: 요청 실패·5xx·전송 오류·드롭된 요청 0건, 응답시간 p99 5초 미만
- 결과: `production/results/<작업-ID>/k6/`
