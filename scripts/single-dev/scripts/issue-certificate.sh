#!/usr/bin/env bash
set -Eeuo pipefail

readonly APP_DIR="${APP_DIR:-/srv/lookddak}"
cd "$APP_DIR"
"${APP_DIR}/scripts/load-parameters.sh"

set -a
# shellcheck disable=SC1091
source .env
set +a

docker compose --env-file .env --profile maintenance run --rm --service-ports \
  certbot certonly --standalone \
  --non-interactive --agree-tos \
  --email "$CERTBOT_EMAIL" \
  -d "$DOMAIN"
