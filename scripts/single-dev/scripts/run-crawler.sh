#!/usr/bin/env bash
set -Eeuo pipefail

readonly APP_DIR="${APP_DIR:-/srv/lookddak}"
readonly MODE="${1:-apply}"

case "$MODE" in
  apply|deliver) ;;
  *) echo "Usage: $0 [apply|deliver]" >&2; exit 2 ;;
esac

cd "$APP_DIR"
"${APP_DIR}/scripts/load-parameters.sh"
docker compose --env-file .env --profile batch run --rm \
  crawler "--${MODE}"
