#!/usr/bin/env bash
# /lookddak/dev/single/* Parameter Store 값을 읽어 /srv/lookddak/.env(권한 600)를 만든다.
# 모든 비밀 값은 Parameter Store에서만 읽는다. deploy.env에는 비밀이 아닌 값만 둔다.
# 필수 Parameter가 없거나, 비어 있거나, Terraform placeholder 그대로면 .env를 갱신하지 않고 실패한다.
set -Eeuo pipefail

readonly APP_DIR="${APP_DIR:-/srv/lookddak}"
readonly DEPLOY_ENV="${APP_DIR}/deploy.env"
readonly RUNTIME_ENV="${APP_DIR}/.env"
export PARAMETER_PREFIX="/lookddak/dev/single"
readonly PARAMETER_PREFIX

[[ -f "$DEPLOY_ENV" ]] || { echo "Missing ${DEPLOY_ENV}" >&2; exit 1; }

set -a
# shellcheck disable=SC1090
source "$DEPLOY_ENV"
set +a

: "${AWS_REGION:=ap-northeast-2}"
: "${DOMAIN:?DOMAIN is required in deploy.env}"

umask 077
PARAMETERS_JSON="$(mktemp)"
trap 'rm -f "$PARAMETERS_JSON" "${RUNTIME_ENV}.tmp"' EXIT

aws ssm get-parameters-by-path \
  --region "$AWS_REGION" \
  --path "$PARAMETER_PREFIX" \
  --recursive \
  --with-decryption \
  --output json >"$PARAMETERS_JSON"

python3 - "$PARAMETERS_JSON" "${RUNTIME_ENV}.tmp" <<'PY'
import json
import os
import sys
import urllib.parse

prefix = os.environ["PARAMETER_PREFIX"] + "/"
placeholder = "PENDING_MANUAL_CONFIGURATION"

with open(sys.argv[1], encoding="utf-8") as f:
    parameters = {
        p["Name"][len(prefix):]: p["Value"]
        for p in json.load(f)["Parameters"]
        if p["Name"].startswith(prefix)
    }

# .env key -> Parameter Store key (prefix 제외)
mapping = {
    "MYSQL_DATABASE": "mysql/database",
    "MYSQL_USER": "mysql/username",
    "MYSQL_PASSWORD": "mysql/password",
    "POSTGRES_DB": "postgresql/database",
    "POSTGRES_USER": "postgresql/username",
    "POSTGRES_PASSWORD": "postgresql/password",
    "JWT_SECRET": "spring/jwt-secret",
    "SPRING_INTERNAL_API_KEY": "spring/internal-api-key",
    "SENTRY_DSN": "spring/sentry-dsn",
    # Dev V2와 동일: BE 수신 키는 SPRING_INTERNAL_API_KEY, BE→AI·AI 수신 키는 AI_INTERNAL_API_KEY.
    # 컨테이너별 INTERNAL_API_KEY는 compose.yaml에서 지정한다.
    "AI_INTERNAL_API_KEY": "internal/ai-api-key",
    "PRICE_REFRESH_BACKEND_AUTH_HEADERS_JSON": "internal/price-refresh-backend-auth-headers",
    "RUNWARE_VTON_API_KEY": "fastapi/runware-vton-api-key",
    "RUNWARE_LLM_API_KEY": "fastapi/runware-llm-api-key",
    "OPENAI_API_KEY": "fastapi/openai-api-key",
    "WEBHOOK_TOKEN": "fastapi/webhook-token",
    "VIRTUAL_FITTING_RUNWARE_WEBHOOK_URL": "fastapi/virtual-fitting-runware-webhook-url",
    "BODY_IMAGE_VALIDATION_URL": "fastapi/body-image-validation/url",
    "BODY_IMAGE_VALIDATION_PROXY_KEY": "fastapi/body-image-validation/proxy-key",
    "BODY_IMAGE_VALIDATION_PROXY_SECRET": "fastapi/body-image-validation/proxy-secret",
    "BODY_IMAGE_VALIDATION_API_KEY": "fastapi/body-image-validation/api-key",
    "MODAL_TOKEN_ID": "fastapi/idm-vton/modal-token-id",
    "MODAL_TOKEN_SECRET": "fastapi/idm-vton/modal-token-secret",
    "S3_BUCKET": "s3/images/bucket",
    "DATABASE_BACKUP_BUCKET": "s3/database-backup/bucket",
    "CLOUDWATCH_LOG_GROUP": "cloudwatch/log-group",
    "BE_FITTING_REQUEST_QUEUE_URL": "sqs/be-fitting-request/url",
    "AI_FITTING_RESPONSE_QUEUE_URL": "sqs/ai-fitting-response/url",
    "BE_FITTING_RESPONSE_QUEUE_URL": "sqs/be-fitting-response/url",
}

missing = sorted({k for k in mapping.values() if k not in parameters})
empty = sorted({k for k in mapping.values() if k in parameters and parameters[k].strip() in ("", "None")})
pending = sorted({k for k in mapping.values() if parameters.get(k) == placeholder})
if missing or empty or pending:
    for label, keys in (("missing", missing), ("empty", empty), ("placeholder", pending)):
        for key in keys:
            print(f"Parameter {label}: {prefix}{key}", file=sys.stderr)
    sys.exit(1)

env = {key: parameters[name] for key, name in mapping.items()}

# 비밀이 아닌 배포 값(deploy.env)
for key in ("AWS_REGION", "DOMAIN", "CERTBOT_EMAIL", "NEXTJS_IMAGE", "SPRING_IMAGE", "FASTAPI_IMAGE", "CRAWLER_IMAGE"):
    env[key] = os.environ.get(key, "")

# 비밀 값이 들어간 연결 문자열은 URL 인코딩해 조합한다.
q = lambda v: urllib.parse.quote(v, safe="")
pg = f"postgresql://{q(env['POSTGRES_USER'])}:{q(env['POSTGRES_PASSWORD'])}@postgres:5432/{q(env['POSTGRES_DB'])}"
env["DATABASE_URL"] = pg
env["CHECKPOINT_DSN"] = f"{pg}?options=-csearch_path%3Dlanggraph"

# Compose env file과 bash source 모두에서 `$` 보간 없이 그대로 읽히도록 작은따옴표로 쓴다.
unsafe = sorted(k for k, v in env.items() if "'" in v or "\n" in v)
if unsafe:
    for key in unsafe:
        print(f"Value for {key} must not contain a single quote or newline", file=sys.stderr)
    sys.exit(1)

with open(sys.argv[2], "w", encoding="utf-8") as f:
    for key in sorted(env):
        f.write(f"{key}='{env[key]}'\n")
PY

mv "${RUNTIME_ENV}.tmp" "$RUNTIME_ENV"
chmod 600 "$RUNTIME_ENV"
echo "Wrote ${RUNTIME_ENV} from ${PARAMETER_PREFIX}"
