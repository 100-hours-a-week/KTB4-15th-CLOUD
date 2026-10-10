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
| `scripts/container-metric.sh` | `/opt/lookddak/scripts/container-metric.sh` | 컨테이너·호스트 상태를 CloudWatch Logs(`/lookddak/prod/status`)로 전송 |
| `scripts/docker-alert.sh` | `/opt/lookddak/scripts/docker-alert.sh` | 컨테이너 상태 변화를 EventBridge로 전송 |
| `systemd/docker-alert.service` | `/etc/systemd/system/docker-alert.service` | `docker-alert.sh` 상시 실행 (systemd) |

## 자동 실행 설정

| 스크립트 | 실행 방식 | 설정 |
|---|---|---|
| `container-metric.sh` | root crontab (1분마다) | `* * * * * /opt/lookddak/scripts/container-metric.sh >> /var/log/container-status.err 2>&1` |
| `docker-alert.sh` | systemd `docker-alert.service` (상시 실행, 종료 시 5초 후 재시작) | `systemd/docker-alert.service` |

> `container-metric.sh` 상단 주석의 `/usr/local/bin/container-metrics.sh`는 이전 경로입니다. 실제로는 위 crontab처럼 `/opt/lookddak/scripts/`의 파일을 실행합니다.


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
