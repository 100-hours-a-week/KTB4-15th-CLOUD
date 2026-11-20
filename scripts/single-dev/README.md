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

## DB 스키마 초기화 (최초 1회)

BE(MySQL)는 기동 시 스키마를 만들지만, AI·Crawler(PostgreSQL)는 각 레포의 SQL을 수동으로 적용해야 한다. 스키마가 없으면 AI가 `no schema has been selected`로 기동에 실패한다.

모든 SQL은 `IF NOT EXISTS`로 작성되어 다시 실행해도 안전하다. 아래 순서로 `psql -v ON_ERROR_STOP=1`로 적용한다.

1. `KTB4-15th-AI/scripts/db/`: `schema.sql` → `usage_amount_split_totals.sql` → `virtual_fitting_pruna_limits.sql` → `virtual_fitting_async_jobs.sql` → `virtual_fitting_fallback.sql` → `virtual_fitting_watchdog.sql` → `virtual_fitting_auth_hold.sql` → `virtual_fitting_runware_image_ref.sql` → `virtual_fitting_ai_result_storage.sql` → `virtual_fitting_pruna_retry.sql`
2. `KTB4-15th-Crawler/price-refresh-crawler/sql/create_price_change_outbox.sql`

```bash
cd /srv/lookddak
set -a; . ./.env; set +a
docker compose --env-file .env exec -T postgres \
  psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" < schema.sql
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

Crawler 이미지 ENTRYPOINT가 `python -m price_refresh`라 스크립트는 모드 인자만 넘긴다. `apply`는 가격을 수집해 PostgreSQL outbox에 기록하고, `deliver`는 대기 중인 결과를 BE에 전달한다.

## 앱 레포 CD

FE·BE·AI·Crawler 레포의 develop push가 다음 순서로 이 서버의 컨테이너를 교체한다. 무중단 배포는 하지 않는다.

1. GitHub Actions(arm64)가 이미지를 빌드해 `lookddak-dev-<서비스>:<7자리 SHA>`로 ECR에 push한다.
2. 레포별 OIDC Role(`gha-lookddak-dev-<서비스>-deploy-role`)로 서비스 전용 SSM Document `lookddak-dev-single-update-<서비스>`를 실행한다.
3. Document가 `scripts/update-image.sh <서비스> <image@digest>`를 실행한다.
   - `deploy.env`의 해당 이미지 줄만 바꾸고 그 컨테이너만 다시 띄운다(crawler는 이미지만 교체).
   - healthy가 되지 않으면 이전 digest로 되돌리고 실패로 끝난다.

배포 Role은 자기 ECR 저장소 push와 자기 서비스 Document 실행만 할 수 있다. Document는 자기 저장소의 `@sha256:` digest 형식만 받는다.

수동 롤백은 각 레포의 dev CD를 이전 이미지 태그로 `workflow_dispatch` 실행하거나, 서버에서 직접 실행한다.

```bash
sudo /srv/lookddak/scripts/update-image.sh spring <account>.dkr.ecr.ap-northeast-2.amazonaws.com/lookddak-dev-spring@sha256:<digest>
```

## 백업

```bash
sudo /srv/lookddak/scripts/backup-db.sh
```

MySQL SQL dump와 PostgreSQL custom-format dump를 신규 Single Dev 백업 버킷에 업로드한다.
