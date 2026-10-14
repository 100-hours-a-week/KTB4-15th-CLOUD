# V1 EC2 서버 파일

V1 애플리케이션 서버(`lookddak-app-v1`)의 `/opt/lookddak`에 배치된 파일을 보관합니다.
EC2는 Terraform으로 관리하지만, **서버 안의 파일은 Terraform 관리 대상이 아니므로** 이 폴더가 원본 기록 역할을 합니다.

## 파일 위치

이 폴더의 구조는 서버의 `/opt/lookddak`와 같습니다. (`systemd/`만 예외로 `/etc/systemd/system`에 배치)

| 저장소 | 서버 | 역할 |
|---|---|---|
| `docker-compose.yaml` | `/opt/lookddak/docker-compose.yaml` | 전체 컨테이너 구성 |
| `nginx/nginx.conf` | `/opt/lookddak/nginx/nginx.conf` | Nginx 기본 설정 |
| `nginx/conf.d/default.conf` | `/opt/lookddak/nginx/conf.d/default.conf` | 도메인·프록시·SSL 설정 |
| `scripts/bootstrap.sh` | `/opt/lookddak/scripts/bootstrap.sh` | 최초 기동 또는 전체 스택 복구 |
| `scripts/deploy.sh` | `/opt/lookddak/scripts/deploy.sh` | 서비스별 배포 (`deploy.sh <fe\|be\|ai> <이미지 태그>`) |
| `scripts/load-parameters.sh` | `/opt/lookddak/scripts/load-parameters.sh` | Parameter Store 조회 함수 (bootstrap·deploy에서 source) |
| `scripts/prepare-pgbouncer.sh` | `/opt/lookddak/scripts/prepare-pgbouncer.sh` | 원본 PostgreSQL의 SCRAM 검증값으로 PgBouncer 런타임 인증 파일 준비 |
| `scripts/container-metric.sh` | `/opt/lookddak/scripts/container-metric.sh` | 컨테이너·호스트 상태를 CloudWatch Logs(`/lookddak/prod/status`)로 전송 |
| `scripts/docker-alert.sh` | `/opt/lookddak/scripts/docker-alert.sh` | 컨테이너 상태 변화를 EventBridge로 전송 |
| `scripts/load-parameters-dev.sh` | dev 서버 `/opt/lookddak/scripts/load-parameters.sh` | dev 서버용 Parameter Store 조회 (`/lookddak/dev/*`) |
| `docker-compose.dev.yaml` | `/opt/lookddak/docker-compose.dev.yaml` | dev 서버 전용 덮어쓰기 (로그 그룹, Nginx 설정) |
| `pgbouncer/pgbouncer.ini` | `/opt/lookddak/pgbouncer/pgbouncer.ini` | Dev PgBouncer 트랜잭션 풀 설정 |
| `pgbouncer/pg_hba.conf` | `/opt/lookddak/pgbouncer/pg_hba.conf` | 앱 SCRAM 인증 및 관리 콘솔 TCP 차단 |
| `pgbouncer/pg_ident.conf` | `/opt/lookddak/pgbouncer/pg_ident.conf` | 컨테이너 내부 관리 사용자 peer 매핑 |
| `nginx/conf.d.dev/default.conf` | `/opt/lookddak/nginx/conf.d.dev/default.conf` | dev 서버 Nginx 설정 |
| `systemd/docker-alert.service` | `/etc/systemd/system/docker-alert.service` | `docker-alert.sh` 상시 실행 (systemd) |

## 자동 실행 설정

| 스크립트 | 실행 방식 | 설정 |
|---|---|---|
| `container-metric.sh` | root crontab (1분마다) | `* * * * * /opt/lookddak/scripts/container-metric.sh >> /var/log/container-status.err 2>&1` |
| `docker-alert.sh` | systemd `docker-alert.service` (상시 실행, 종료 시 5초 후 재시작) | `systemd/docker-alert.service` |

> `container-metric.sh` 상단 주석의 `/usr/local/bin/container-metrics.sh`는 이전 경로입니다. 실제로는 위 crontab처럼 `/opt/lookddak/scripts/`의 파일을 실행합니다.


## prod / dev 구분

같은 파일을 prod 서버(`lookddak.com`)와 dev 서버(`dev.lookddak.com`)에서 함께 사용하고, dev에만 필요한 차이는 dev 전용 파일로 둡니다.

| dev 전용 파일 | dev 서버 배치 경로 | prod와 다른 점 |
|---|---|---|
| `scripts/load-parameters-dev.sh` | `/opt/lookddak/scripts/load-parameters.sh` (**이 이름으로 복사**) | Parameter Store 경로가 `/lookddak/dev/...` |
| `docker-compose.dev.yaml` | `/opt/lookddak/docker-compose.dev.yaml` | 아래 덮어쓰기 내용 |
| `pgbouncer/*` | `/opt/lookddak/pgbouncer/*` | Dev FastAPI 앞의 PgBouncer 설정 (`userlist.txt` 제외) |
| `scripts/prepare-pgbouncer.sh` | `/opt/lookddak/scripts/prepare-pgbouncer.sh` | PgBouncer 인증 파일 생성 및 고정 이미지 준비 |
| `nginx/conf.d.dev/default.conf` | `/opt/lookddak/nginx/conf.d.dev/default.conf` | 도메인 `dev.lookddak.com`, www 리다이렉트 없음 |

- `load-parameters-dev.sh`를 `load-parameters.sh` 이름으로 복사하므로 `bootstrap.sh`, `deploy.sh`는 prod와 같은 파일을 그대로 사용합니다.
- dev 서버 `.env`에 `COMPOSE_FILE=docker-compose.yaml:docker-compose.dev.yaml`을 넣으면 docker compose가 두 파일을 합쳐서 사용합니다.
- dev 서버 `.env`에 `ECR_REPOSITORY_PREFIX=lookddak-dev`를 넣으면 이미지를 dev ECR(`lookddak-dev-nextjs` 등)에서 받습니다. 값이 없으면 prod 저장소(`lookddak-nextjs` 등)를 사용합니다. (`docker-compose.yaml`, `deploy.sh` 공통)

`docker-compose.dev.yaml`이 바꾸는 것

| 항목 | prod | dev |
|---|---|---|
| 컨테이너 로그 그룹 | CloudWatch Logs `/lookddak/prod/*` | CloudWatch Logs `/lookddak/dev/*` |
| Nginx 설정 | `nginx/conf.d` | `nginx/conf.d.dev` |
| FastAPI의 PostgreSQL 연결 | PostgreSQL 5432 직접 연결 | PgBouncer 6432 경유 (`pool_mode=transaction`) |
| PgBouncer 서비스 | 없음 | `edoburu/pgbouncer:v1.26.0-p0` digest 고정 |

dev 서버는 로그 수집만 하고 알림은 두지 않습니다. 모니터링(`container-metric.sh` cron, `docker-alert.sh` systemd)을 설치하지 않습니다.

## Dev PgBouncer

- PgBouncer는 Dev 오버레이에만 있으며 포트를 호스트에 공개하지 않습니다. FastAPI와 PostgreSQL이 함께 쓰는 `db-network` 안에서만 6432 포트로 접근합니다.
- `pool_mode=transaction`, `max_prepared_statements=200`, `track_extra_parameters=search_path`로 설정합니다. LangGraph의 `options=-csearch_path=langgraph`도 유지합니다.
- 관리 콘솔은 컨테이너 내부 Unix 소켓의 `pgbouncer_admin`만 허용합니다. TCP 관리 콘솔 접속은 HBA에서 거부합니다.
- `pgbouncer/userlist.txt`에는 원본 PostgreSQL의 SCRAM 검증값이 들어가므로 Git에 넣지 않습니다. `prepare-pgbouncer.sh`가 평문 비밀번호를 출력하지 않고 서버에서 생성합니다.
- `bootstrap.sh`는 PostgreSQL과 `langgraph` 스키마를 먼저 준비한 뒤 PgBouncer를 기동합니다. `deploy.sh ai ...`도 FastAPI 전환 전에 PgBouncer 헬스체크를 확인합니다.
- 이 구성은 PostgreSQL 컨테이너 설정과 `wal_level`을 변경하거나 PostgreSQL을 재시작하지 않습니다.

서버에서 수동으로 다시 준비할 때는 다음 순서로 실행합니다.

```bash
sudo /opt/lookddak/scripts/prepare-pgbouncer.sh
sudo docker compose -f /opt/lookddak/docker-compose.yaml -f /opt/lookddak/docker-compose.dev.yaml up -d --no-deps pgbouncer
sudo docker compose -f /opt/lookddak/docker-compose.yaml -f /opt/lookddak/docker-compose.dev.yaml up -d --no-deps --force-recreate fastapi
sudo docker exec lookddak-pgbouncer psql -X -h /var/run/pgbouncer -p 6432 -U pgbouncer_admin -d pgbouncer -c 'SHOW POOLS;'
```

## 서버 반영

현재는 자동 동기화가 없습니다. 이 폴더의 파일을 수정했다면 PR merge 후 서버의 같은 경로에 직접 반영합니다.
반대로 서버에서 직접 수정했다면 이 폴더에도 같은 내용을 PR로 올립니다.

## 복구

EC2를 새로 만든 경우 아래 순서로 진행합니다. EC2·EIP·IAM 인스턴스 프로파일은 Terraform으로 먼저 복구되어 있어야 합니다.

### 1. 파일 배치

이 폴더의 파일을 `/opt/lookddak`에 같은 구조로 복사합니다. (`systemd/`는 3번에서 따로 배치)

### 2. bootstrap 전에 직접 해야 하는 작업

`bootstrap.sh`는 아래 두 작업을 하지 않으므로, 하지 않으면 컨테이너가 기동되지 않습니다.

**PostgreSQL 데이터 폴더 생성**

`postgresql-data` 볼륨은 호스트 폴더를 그대로 연결(bind)하는 방식이라 폴더가 미리 있어야 합니다.

```bash
sudo mkdir -p /srv/lookddak/postgresql
```

**SSL 인증서 발급**

`nginx/conf.d/default.conf`가 443 포트에서 `/etc/nginx/ssl/live/lookddak.com/` 인증서를 읽으므로, 인증서가 없으면 Nginx가 기동되지 않습니다.
Nginx가 꺼진 상태에서 certbot standalone 모드(certbot이 직접 80 포트 사용)로 발급합니다.

```bash
cd /opt/lookddak
sudo docker compose --profile ssl run --rm -p 80:80 certbot certonly --standalone \
  -d lookddak.com -d www.lookddak.com \
  --agree-tos --non-interactive -m <관리자 이메일>
```

- `lookddak.com` A 레코드가 새 서버의 IP(EIP)를 가리키고 있어야 발급됩니다.
- 인증서와 개인 키는 `certbot-certs` 볼륨에 저장됩니다. 개인 키가 포함되므로 저장소에 넣지 않고, 서버를 새로 만들 때마다 재발급합니다.

### 3. 기동 및 자동 실행 등록

```bash
sudo /opt/lookddak/scripts/bootstrap.sh

# docker-alert (systemd)
sudo cp systemd/docker-alert.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now docker-alert.service

# container-metric (root crontab에 아래 줄 추가)
sudo crontab -e
# * * * * * /opt/lookddak/scripts/container-metric.sh >> /var/log/container-status.err 2>&1
```

### 데이터

`postgresql-data` 볼륨(`/srv/lookddak/postgresql`)의 데이터는 저장소로 복구할 수 없습니다. 새 서버에서는 빈 DB로 시작하며, 데이터 복구가 필요하면 별도 백업이 있어야 합니다.
