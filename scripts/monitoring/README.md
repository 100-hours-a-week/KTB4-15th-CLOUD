# dev 모니터링 서버 파일

dev 모니터링 서버(`lookddak-dev-monitoring`, `10.30.21.250`)의 `/opt/monitoring`에 배치하는 파일입니다.
EC2는 Terraform(`infra/environments/dev/v2/observability`)으로 관리하고, 서버 안의 파일은 이 폴더가 원본입니다.

## 파일 위치

| 저장소 | 서버 | 역할 |
|---|---|---|
| `docker-compose.yaml` | `/opt/monitoring/docker-compose.yaml` | Prometheus, Loki, Alloy, Grafana, Tempo, DB exporter (MySQL, PostgreSQL), db-log-tailer |
| `prometheus/prometheus.yml` | `/opt/monitoring/prometheus/prometheus.yml` | 모니터링 구성요소, ECS Task, 앱, DB exporter scrape |
| `loki/config.yaml` | `/opt/monitoring/loki/config.yaml` | 단일 바이너리, S3 저장, 보존 7일 |
| `tempo/config.yaml` | `/opt/monitoring/tempo/config.yaml` | Tempo 3.1 단일 바이너리, OTLP 수신(내부), S3 저장, 보존 7일, metrics-generator(서비스 그래프·스팬 지표 → Prometheus) |
| `alloy/config.alloy` | `/opt/monitoring/alloy/config.alloy` | 호스트 메트릭·AWS 메트릭(YACE) → Prometheus, Loki push 수신(:3500) → Loki |
| `grafana/provisioning/datasources/datasources.yaml` | `/opt/monitoring/grafana/provisioning/datasources/datasources.yaml` | Prometheus, Loki, CloudWatch 데이터소스 |
| `grafana/provisioning/dashboards/dashboards.yaml` | `/opt/monitoring/grafana/provisioning/dashboards/dashboards.yaml` | 대시보드 JSON 폴더를 읽는 provider (UI 수정 불가, 파일이 원본) |
| `grafana/provisioning/dashboards/json/aws-overview.json` | `/opt/monitoring/grafana/provisioning/dashboards/json/aws-overview.json` | AWS Overview: ALB·ECS·RDS |
| `grafana/provisioning/dashboards/json/queue.json` | `/opt/monitoring/grafana/provisioning/dashboards/json/queue.json` | Queue: SQS·DLQ |
| `grafana/provisioning/dashboards/json/ecs-task.json` | `/opt/monitoring/grafana/provisioning/dashboards/json/ecs-task.json` | ECS Task: Task·컨테이너 CPU·메모리, 네트워크, 중지 이벤트, 앱 로그 |
| `grafana/provisioning/dashboards/json/spring-api.json` | `/opt/monitoring/grafana/provisioning/dashboards/json/spring-api.json` | Spring API: HTTP 요청·오류·응답 시간, HikariCP, JVM |
| `grafana/provisioning/dashboards/json/ai-worker.json` | `/opt/monitoring/grafana/provisioning/dashboards/json/ai-worker.json` | AI Worker: 가상피팅 Worker 상태·처리량, HTTP |
| `grafana/provisioning/dashboards/json/database.json` | `/opt/monitoring/grafana/provisioning/dashboards/json/database.json` | Database: MySQL·PostgreSQL 연결, 쿼리·트랜잭션, 캐시 적중률, 락, dead tuple, 복제 슬롯, 쿼리 로그(전체·실패·느린 쿼리, PG 오류) |
| `db-log-tailer/` (`Dockerfile`, `tailer.py`) | `/opt/monitoring/db-log-tailer/` | DB 쿼리 로그 수집기. RDS 로그 파일(MySQL 감사 로그, PostgreSQL 로그)을 RDS API로 이어 읽어 Alloy(:3500)로 보냄. `docker compose build db-log-tailer` 후 `up -d` |

`/opt/monitoring/.env`는 저장소에 두지 않습니다. 배포할 때 서버에서 만듭니다.

| 변수 | 값 |
|---|---|
| `GRAFANA_ADMIN_PASSWORD` | Parameter Store `/lookddak/dev/monitoring/grafana-admin-password` |
| `LOKI_S3_BUCKET` | `lookddak-dev-loki-<계정 ID>-ap-northeast-2` (Terraform 출력 `loki_bucket_name`) |
| `TEMPO_S3_BUCKET` | `lookddak-dev-tempo-<계정 ID>-ap-northeast-2` (Terraform 출력 `tempo_bucket_name`) |
| `POSTGRES_EXPORTER_HOST` | Parameter Store `/lookddak/dev/v2/postgresql/host` |
| `POSTGRES_EXPORTER_PASSWORD` | Parameter Store `/lookddak/dev/monitoring/postgres-exporter/password` |

서버에서만 만드는 파일 (저장소에 두지 않음):

| 서버 | 내용 |
|---|---|
| `/opt/monitoring/rds-ca/global-bundle.pem` | RDS CA 인증서 (`https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem`) |
| `/opt/monitoring/mysqld-exporter/my.cnf` | `[client]` host, port, user(`exporter`), password(`/lookddak/dev/monitoring/mysql-exporter/password`), `ssl-ca`. 소유자 65534, 권한 0400 |

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
| `/lookddak/dev/monitoring/grafana-admin-password` | SecureString | Grafana `admin` 비밀번호 |
| `/lookddak/dev/monitoring/mysql-exporter/password` | SecureString | MySQL `exporter` 계정 (`PROCESS, REPLICATION CLIENT`, `performance_schema` 읽기, `REQUIRE SSL`, 접속 호스트 `10.30.21.250`) |
| `/lookddak/dev/monitoring/postgres-exporter/password` | SecureString | PostgreSQL `exporter` 계정 (`pg_monitor`) |

## 데이터

Docker named volume(`prometheus-data`, `loki-data`, `alloy-data`, `grafana-data`)에 저장합니다. 루트 디스크(30GB) 하나만 쓰므로 Prometheus는 `retention.size=10GB`로 제한합니다. Loki 로그는 S3에 7일 보존하고, 로컬 볼륨에는 WAL·캐시만 둡니다. 인스턴스를 교체하면 메트릭은 사라집니다 (dev).

## 접속

팀원: `https://grafana.dev.lookddak.com` → Cognito 로그인 → Grafana 자동 로그인 (Editor).

- ALB가 Cognito 인증 후 `X-Amzn-Oidc-Identity`(Cognito 사용자 ID, UUID) 헤더를 붙여 전달하고, Grafana auth proxy가 이 값으로 로그인시킵니다.
- 헤더는 ALB 서브넷(`10.30.1.0/24`, `10.30.2.0/24`)에서 온 요청만 인정합니다.
- 계정은 관리자가 Cognito 사용자 풀 `lookddak-dev-grafana`에 만듭니다 (셀프 가입 없음).

관리자(`admin`): SSM 포트포워딩 후 `http://localhost:3000/login` (`admin` / Parameter Store 비밀번호).

```bash
aws ssm start-session --target <instance-id> --document-name AWS-StartPortForwardingSession --parameters portNumber=3000,localPortNumber=3000
```

## 설정 반영

설정 폴더(`prometheus/`, `loki/`, `alloy/`, `grafana/provisioning/`)는 파일이 아니라 폴더째 컨테이너에 연결한다. 파일을 `install`로 바꿔 넣으면 컨테이너가 바로 새 내용을 본다.

| 바꾼 파일 | 반영 방법 |
|---|---|
| `prometheus/prometheus.yml` | `curl -X POST localhost:9090/-/reload` |
| `alloy/config.alloy` | `curl -X POST localhost:12345/-/reload` |
| `loki/config.yaml` | `docker compose restart loki` |
| `tempo/config.yaml` | `docker compose restart tempo` |
| Grafana 대시보드 JSON | 자동 (60초 안에 다시 읽음) |
| Grafana 데이터소스, `docker-compose.yaml` | `docker compose up -d` |

