# dev 모니터링 서버 파일

dev 모니터링 서버(`lookddak-dev-monitoring`, `10.30.21.250`)의 `/opt/monitoring`에 배치하는 파일입니다.
EC2는 Terraform(`infra/environments/dev/v2/observability`)으로 관리하고, 서버 안의 파일은 이 폴더가 원본입니다.

## 파일 위치

| 저장소 | 서버 | 역할 |
|---|---|---|
| `docker-compose.yaml` | `/opt/monitoring/docker-compose.yaml` | Prometheus, Loki, Alloy, Grafana |
| `prometheus/prometheus.yml` | `/opt/monitoring/prometheus/prometheus.yml` | 모니터링 구성요소 scrape |
| `loki/config.yaml` | `/opt/monitoring/loki/config.yaml` | 단일 바이너리, 파일시스템 저장, 보존 7일 |
| `alloy/config.alloy` | `/opt/monitoring/alloy/config.alloy` | 호스트 메트릭·AWS 메트릭(YACE) → Prometheus, Loki push 수신(:3500) → Loki |
| `grafana/provisioning/datasources/datasources.yaml` | `/opt/monitoring/grafana/provisioning/datasources/datasources.yaml` | Prometheus, Loki, CloudWatch 데이터소스 |
| `grafana/provisioning/dashboards/dashboards.yaml` | `/opt/monitoring/grafana/provisioning/dashboards/dashboards.yaml` | 대시보드 JSON 폴더를 읽는 provider (UI 수정 불가, 파일이 원본) |
| `grafana/provisioning/dashboards/json/aws-overview.json` | `/opt/monitoring/grafana/provisioning/dashboards/json/aws-overview.json` | AWS Overview: ALB·ECS·RDS |
| `grafana/provisioning/dashboards/json/queue.json` | `/opt/monitoring/grafana/provisioning/dashboards/json/queue.json` | Queue: SQS·DLQ |

`/opt/monitoring/.env`는 저장소에 두지 않습니다. 배포할 때 Parameter Store에서 만듭니다.

## 포트

| 포트 | 대상 | 열린 범위 |
|---|---|---|
| 3000 | Grafana | 호스트 (SSM 포트포워딩, 이후 ALB) |
| 3500 | Alloy Loki push 수신 | 호스트 (이후 ECS task, lambda-promtail) |
| 9090 | Prometheus | 127.0.0.1 |
| 3100 | Loki | 127.0.0.1 |
| 12345 | Alloy UI | 127.0.0.1 |

보안 그룹 인바운드는 별도 PR에서 필요한 포트만 엽니다.

## Parameter Store (콘솔에서 수동 생성)

| 이름 | 타입 | 용도 |
|---|---|---|
| `/lookddak/dev/monitoring/grafana-admin-password` | SecureString | Grafana `admin` 비밀번호 |

## 데이터

Docker named volume(`prometheus-data`, `loki-data`, `alloy-data`, `grafana-data`)에 저장합니다. 루트 디스크(30GB) 하나만 쓰므로 Prometheus는 `retention.size=10GB`, Loki는 7일 보존으로 제한합니다. 인스턴스를 교체하면 데이터는 사라집니다 (dev).

## 접속

```bash
aws ssm start-session --target <instance-id> --document-name AWS-StartPortForwardingSession --parameters portNumber=3000,localPortNumber=3000
```

브라우저에서 `http://localhost:3000` 접속 (`admin` / Parameter Store 비밀번호).
