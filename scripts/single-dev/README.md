# Single Dev Docker Compose

단일 ARM64 EC2에서 룩딱 개발 서비스를 운영하는 Compose 구성이다. Kubernetes의 역할별 Pod를 그대로 옮기지 않고 동일 이미지의 기능을 FE·BE·AI 컨테이너로 통합한다.

## 서비스 구성

| 구분 | 서비스 | 실행 방식 |
|---|---|---|
| 상시 | `nginx`, `frontend`, `backend`, `ai`, `mysql`, `postgres` | `docker compose up -d` |
| 수동 | `crawler` | `batch` profile |
| 관리 | `certbot` | `maintenance` profile |

- 기존 Dev V2 Fitting Queue 3개를 그대로 사용한다. 이 구성은 Queue나 DLQ를 생성·변경·삭제하지 않는다.
- MySQL과 PostgreSQL 데이터는 별도 EBS가 마운트된 `/srv/lookddak/data`에 저장한다.
- 비밀 값은 `/lookddak/dev/single/*` Parameter Store에서 읽어 `/srv/lookddak/.env`에 권한 `600`으로 생성한다.
- 애플리케이션 이미지는 ECR digest로 고정한다.

## 최초 배치

```bash
sudo ./scripts/bootstrap.sh
sudo install -d -m 0755 /srv/lookddak
sudo cp -R compose.yaml nginx scripts /srv/lookddak/
sudo cp deploy.env.example /srv/lookddak/deploy.env
sudo chmod +x /srv/lookddak/scripts/*.sh
```

`/srv/lookddak/deploy.env`에서 도메인, 이메일, 네 이미지 digest를 실제 값으로 변경한다. `deploy.env`에는 비밀이 아닌 값만 둔다.

## 비밀 값

모든 비밀 값은 `/lookddak/dev/single/*` Parameter Store에서만 읽는다. `load-parameters.sh`가 경로 전체를 한 번에 조회해 `/srv/lookddak/.env`(권한 `600`)를 만든다.

- 필수 Parameter가 없거나, 비어 있거나, `PENDING_MANUAL_CONFIGURATION` 그대로면 `.env`를 갱신하지 않고 실패한다. 따라서 placeholder 상태로 DB가 초기화되지 않는다.
- 값은 Terraform state에 남지 않도록 콘솔 또는 `aws ssm put-parameter --overwrite`로 직접 입력한다.
- `fastapi/virtual-fitting-runware-webhook-url`은 `https://<DOMAIN>/api/v2/webhooks/runware?token=<URL 인코딩한 webhook-token>` 형식으로 입력한다.
- PostgreSQL 연결 문자열(`DATABASE_URL`, `CHECKPOINT_DSN`)은 비밀 값을 URL 인코딩해 스크립트에서 조합한다.
- `.env`는 Compose와 bash 양쪽에서 `$` 보간 없이 읽히도록 작은따옴표로 기록하므로, 값에 작은따옴표와 줄바꿈은 쓸 수 없다.

도메인의 A 레코드를 EC2 EIP로 연결한 뒤 인증서를 발급하고 배포한다.

```bash
sudo /srv/lookddak/scripts/issue-certificate.sh
sudo /srv/lookddak/scripts/deploy.sh
```

## 확인

```bash
cd /srv/lookddak
sudo docker compose --env-file .env ps
sudo bash -c 'set -a; source .env; curl -fsS "https://${DOMAIN}/healthz"'
```

상시 6개 컨테이너가 모두 `healthy`여야 한다.

## Crawler 수동 실행

```bash
sudo /srv/lookddak/scripts/run-crawler.sh apply
sudo /srv/lookddak/scripts/run-crawler.sh deliver
```

`apply`는 가격을 수집해 PostgreSQL outbox에 기록하고, `deliver`는 대기 중인 결과를 BE에 전달한다.

## 백업

```bash
sudo /srv/lookddak/scripts/backup-db.sh
```

MySQL SQL dump와 PostgreSQL custom-format dump를 신규 Single Dev 백업 버킷에 업로드한다.
