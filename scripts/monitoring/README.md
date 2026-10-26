# 모니터링 서버 파일 (dev, prod)

모니터링 서버의 `/opt/monitoring`에 배치하는 파일입니다. dev와 prod가 같은 파일을 쓰고, 환경별 값은 서버 `.env`에 둡니다 (Prometheus만 환경별 파일).
EC2는 Terraform(`infra/modules/observability`)으로 관리하고, 서버 안의 파일은 이 폴더가 원본입니다.

| 환경 | 서버 | 고정 IP | Grafana |
|---|---|---|---|
| dev | `lookddak-dev-monitoring` | `10.30.21.250` | `https://grafana.dev.lookddak.com` (ALB 직접) |
| prod | `lookddak-prod-monitoring` | `10.20.21.250` | `https://grafana.lookddak.com` (CloudFront → ALB) |

## 파일 위치

| 저장소 | 서버 | 역할 |
|---|---|---|
| `docker-compose.yaml` | `/opt/monitoring/docker-compose.yaml` | Prometheus, Loki, Alloy, Grafana, Tempo, DB exporter (MySQL, PostgreSQL), db-log-tailer |
| `prometheus/prometheus.dev.yml`, `prometheus/prometheus.prod.yml` | `/opt/monitoring/prometheus/` (둘 다) | 모니터링 구성요소, ECS Task, 앱, DB exporter scrape. `MONITORING_ENV`로 고른다. 클러스터·서비스·DB 이름만 다르니 함께 고친다 |
| `loki/config.yaml` | `/opt/monitoring/loki/config.yaml` | 단일 바이너리, S3 저장, 보존 7일 |
| `tempo/config.yaml` | `/opt/monitoring/tempo/config.yaml` | Tempo 3.1 단일 바이너리, OTLP 수신(내부), S3 저장, 보존 7일, metrics-generator(서비스 그래프·스팬 지표 → Prometheus) |
| `alloy/config.alloy` | `/opt/monitoring/alloy/config.alloy` | 호스트 메트릭·AWS 메트릭(YACE) → Prometheus, Loki push 수신(:3500) → Loki |
| `grafana/provisioning/datasources/datasources.yaml` | `/opt/monitoring/grafana/provisioning/datasources/datasources.yaml` | Prometheus, Loki, CloudWatch 데이터소스 |
| `grafana/provisioning/dashboards/dashboards.yaml` | `/opt/monitoring/grafana/provisioning/dashboards/dashboards.yaml` | 대시보드 JSON 폴더를 읽는 provider (UI 수정 불가, 파일이 원본) |
| `grafana/provisioning/dashboards/json/aws-overview.json` | `/opt/monitoring/grafana/provisioning/dashboards/json/aws-overview.json` | AWS Overview: ALB·ECS·RDS |
| `grafana/provisioning/dashboards/json/queue.json` | `/opt/monitoring/grafana/provisioning/dashboards/json/queue.json` | Queue: SQS·DLQ |
| `grafana/provisioning/dashboards/json/ecs-task.json` | `/opt/monitoring/grafana/provisioning/dashboards/json/ecs-task.json` | 서비스 별 지표 및 로그(Grafana 홈): Task·컨테이너 CPU·메모리, 네트워크, 중지 이벤트, 앱 로그, 트레이스(서비스 그래프·느린 요청·에러) |
| `grafana/provisioning/dashboards/json/spring-api.json` | `/opt/monitoring/grafana/provisioning/dashboards/json/spring-api.json` | Spring 내부 지표: HTTP 요청·오류·응답 시간, HikariCP, JVM |
| `grafana/provisioning/dashboards/json/ai-worker.json` | `/opt/monitoring/grafana/provisioning/dashboards/json/ai-worker.json` | FastAPI 내부 지표: 가상피팅 Worker 상태·처리량, HTTP |
| `grafana/provisioning/dashboards/json/database.json` | `/opt/monitoring/grafana/provisioning/dashboards/json/database.json` | Database: MySQL·PostgreSQL 연결, 쿼리·트랜잭션, 캐시 적중률, 락, dead tuple, 복제 슬롯, 쿼리 로그(전체·실패·느린 쿼리, PG 오류) |
| `grafana/provisioning/dashboards/json/traces.json` | `/opt/monitoring/grafana/provisioning/dashboards/json/traces.json` | 트레이스 (DB·가상피팅·채팅): Tempo span 지표와 TraceQL로 DB 쿼리, 피팅 API·SQS·웹훅, 채팅·AI 스트림 |
| `db-log-tailer/` (`Dockerfile`, `tailer.py`) | `/opt/monitoring/db-log-tailer/` | DB 쿼리 로그 수집기. RDS 로그 파일(MySQL 감사·오류·슬로우 쿼리 로그, PostgreSQL 로그)을 RDS API로 이어 읽어 Alloy(:3500)로 보냄. `docker compose build db-log-tailer` 후 `up -d` |

`/opt/monitoring/.env`는 저장소에 두지 않습니다. 배포할 때 서버에서 만듭니다.

`<env>`는 `dev` 또는 `prod`입니다.

| 변수 | dev | prod |
|---|---|---|
| `MONITORING_ENV` | `dev` | `prod` |
| `GRAFANA_ROOT_URL` | `https://grafana.dev.lookddak.com` | `https://grafana.lookddak.com` |
| `GRAFANA_PROXY_WHITELIST` (ALB 서브넷) | `10.30.1.0/24, 10.30.2.0/24` | `10.20.1.0/24, 10.20.2.0/24` |
| `DB_LOG_TARGETS` | `mysql:lookddak-dev-v2-mysql:audit/,mysql:lookddak-dev-v2-mysql:error/,mysql:lookddak-dev-v2-mysql:slowquery/,postgresql:lookddak-dev-postgresql:error/postgresql.log` | `mysql:lookddak-prod-v2-mysql:error/,mysql:lookddak-prod-v2-mysql:slowquery/,postgresql:lookddak-prod-v2-postgresql:error/postgresql.log` (쿼리 로그는 DB 설정 후 추가) |
| `GRAFANA_ADMIN_PASSWORD` | Parameter Store `/lookddak/<env>/monitoring/grafana-admin-password` | 같음 |
| `LOKI_S3_BUCKET` | `lookddak-<env>-loki-<계정 ID>-ap-northeast-2` (Terraform 출력 `loki_bucket_name`) | 같음 |
| `TEMPO_S3_BUCKET` | `lookddak-<env>-tempo-<계정 ID>-ap-northeast-2` (Terraform 출력 `tempo_bucket_name`) | 같음 |
| `POSTGRES_EXPORTER_HOST` | Parameter Store `/lookddak/<env>/v2/postgresql/host` | 같음 |
| `POSTGRES_EXPORTER_PASSWORD` | Parameter Store `/lookddak/<env>/monitoring/postgres-exporter/password` | 같음 |

서버에서만 만드는 파일 (저장소에 두지 않음):

| 서버 | 내용 |
|---|---|
| `/opt/monitoring/rds-ca/global-bundle.pem` | RDS CA 인증서 (`https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem`) |
| `/opt/monitoring/mysqld-exporter/my.cnf` | `[client]` host, port, user(`exporter`), password(`/lookddak/<env>/monitoring/mysql-exporter/password`), `ssl-ca`. 소유자 65534, 권한 0400 |

## 포트

| 포트 | 대상 | 열린 범위 |
|---|---|---|
| 3000 | Grafana | 호스트 (ALB 보안 그룹, SSM 포트포워딩) |
| 3500 | Alloy Loki push 수신 | 호스트 (lambda-promtail, ECS Task FireLens) |
| 4317 | Alloy OTLP gRPC 트레이스 수신 (spring) | 호스트 (ECS Task, SG로 nextjs·spring·fastapi만) |
| 4318 | Alloy OTLP HTTP 트레이스 수신 (nextjs·fastapi) | 호스트 (ECS Task, SG로 nextjs·spring·fastapi만) |
| 3200 | Tempo 조회 API | 127.0.0.1 |
| 9090 | Prometheus | 127.0.0.1 |
| 3100 | Loki (저장소: S3) | 127.0.0.1 |
| 12345 | Alloy UI | 127.0.0.1 |
| 9104 | mysqld-exporter | 127.0.0.1 |
| 9187 | postgres-exporter | 127.0.0.1 |
| 9200 | db-log-tailer 지표 | 127.0.0.1 |

보안 그룹 인바운드는 별도 PR에서 필요한 포트만 엽니다.

## Parameter Store (콘솔에서 수동 생성)

| 이름 | 타입 | 용도 |
|---|---|---|
| `/lookddak/<env>/monitoring/grafana-admin-password` | SecureString | Grafana `admin` 비밀번호 |
| `/lookddak/<env>/monitoring/mysql-exporter/password` | SecureString | MySQL `exporter` 계정 (`PROCESS, REPLICATION CLIENT`, `performance_schema` 읽기, `REQUIRE SSL`, 접속 호스트는 모니터링 서버 고정 IP) |
| `/lookddak/<env>/monitoring/postgres-exporter/password` | SecureString | PostgreSQL `exporter` 계정 (`pg_monitor`) |

## 데이터

Docker named volume(`prometheus-data`, `loki-data`, `alloy-data`, `grafana-data`)에 저장합니다. 루트 디스크(30GB) 하나만 쓰므로 Prometheus는 `retention.size=10GB`로 제한합니다. Loki 로그는 S3에 7일 보존하고, 로컬 볼륨에는 WAL·캐시만 둡니다. 인스턴스를 교체하면 메트릭은 사라집니다.

## 접속

팀원: Grafana 주소(위 표) → Cognito 로그인 → Grafana 자동 로그인 (Editor).

- ALB가 Cognito 인증 후 `X-Amzn-Oidc-Identity`(Cognito 사용자 ID, UUID) 헤더를 붙여 전달하고, Grafana auth proxy가 이 값으로 로그인시킵니다.
- 헤더는 ALB 서브넷(`GRAFANA_PROXY_WHITELIST`)에서 온 요청만 인정합니다.
- 계정은 관리자가 Cognito 사용자 풀 `lookddak-<env>-grafana`에 만듭니다 (셀프 가입 없음).
- prod는 CloudFront가 원본 검증 헤더를 붙여 ALB로 보냅니다. ALB 주소로 직접 들어오면 403입니다.

관리자(`admin`): SSM 포트포워딩 후 `http://localhost:3000/login` (`admin` / Parameter Store 비밀번호).

```bash
aws ssm start-session --target <instance-id> --document-name AWS-StartPortForwardingSession --parameters portNumber=3000,localPortNumber=3000
```

## 설정 반영

설정 폴더(`prometheus/`, `loki/`, `alloy/`, `grafana/provisioning/`)는 파일이 아니라 폴더째 컨테이너에 연결한다. 파일을 `install`로 바꿔 넣으면 컨테이너가 바로 새 내용을 본다.

| 바꾼 파일 | 반영 방법 |
|---|---|
| `prometheus/prometheus.<env>.yml` | `curl -X POST localhost:9090/-/reload` |
| `alloy/config.alloy` | `curl -X POST localhost:12345/-/reload` |
| `loki/config.yaml` | `docker compose restart loki` |
| `tempo/config.yaml` | `docker compose restart tempo` |
| Grafana 대시보드 JSON | 자동 (60초 안에 다시 읽음) |
| Grafana 데이터소스, `docker-compose.yaml` | `docker compose up -d` |


## 새 환경 준비 (prod 처음 한 번)

1. Terraform apply 전: lambda-promtail ZIP을 `lookddak-<env>-lambda-artifacts-<계정 ID>-ap-northeast-2` 버킷 `lambda-promtail/v1.0.1/lambda-promtail-v1.0.1.zip`에 올린다 (sha256 `2a436a30772ac638f715dd240784f787b9f0c745ba292a49cd23d132c477fd13` 확인). 없으면 apply가 Lambda 생성에서 실패한다.
2. Parameter Store 3개 생성 (위 표).
3. DB에 `exporter` 계정 생성 (MySQL: 접속 호스트 = 서버 고정 IP, PostgreSQL: `pg_monitor`).
4. 서버(`sudo su`)에서 `/opt/monitoring`에 이 폴더 파일을 커밋 해시로 받아 sha256 확인 후 `install`, `.env`·`rds-ca/`·`mysqld-exporter/my.cnf` 생성.
5. `docker compose build db-log-tailer && docker compose up -d`
6. Cognito 사용자 풀 `lookddak-<env>-grafana`에 팀원 계정 생성.
