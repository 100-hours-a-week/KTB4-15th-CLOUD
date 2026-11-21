#!/usr/bin/env bash
set -Eeuo pipefail

readonly APP_DIR="${APP_DIR:-/srv/lookddak}"
cd "$APP_DIR"

"${APP_DIR}/scripts/load-parameters.sh"

set -a
# shellcheck disable=SC1091
source .env
set +a

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
aws ecr get-login-password --region "$AWS_REGION" | \
  docker login --username AWS --password-stdin "${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

docker compose --env-file .env config --quiet
docker compose --env-file .env pull

docker compose --env-file .env up -d mysql postgres redis
docker compose --env-file .env up -d ai backend frontend

if [[ ! -s "/srv/lookddak/certbot/conf/live/${DOMAIN}/fullchain.pem" ]]; then
  echo "TLS certificate is missing for ${DOMAIN}. Run scripts/issue-certificate.sh, then rerun deploy.sh." >&2
  exit 1
fi

docker compose --env-file .env up -d nginx
docker compose --env-file .env ps
