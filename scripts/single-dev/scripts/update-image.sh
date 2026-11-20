#!/usr/bin/env bash
# 앱 레포 develop CD가 SSM Document로 실행한다.
#   update-image.sh <nextjs|spring|fastapi|crawler> <ECR image@sha256:digest>
# 지정한 서비스의 이미지만 교체하고 healthy를 기다린다. 실패하면 이전 이미지로 되돌린다.
# 무중단 배포는 하지 않는다(해당 컨테이너만 재시작).
set -Eeuo pipefail

readonly APP_DIR="${APP_DIR:-/srv/lookddak}"
readonly DEPLOY_ENV="${APP_DIR}/deploy.env"
readonly SERVICE_KEY="${1:-}"
readonly IMAGE="${2:-}"
readonly HEALTH_TIMEOUT_SECONDS="${HEALTH_TIMEOUT_SECONDS:-420}"

case "$SERVICE_KEY" in
  nextjs)  ENV_KEY=NEXTJS_IMAGE;  SERVICE=frontend ;;
  spring)  ENV_KEY=SPRING_IMAGE;  SERVICE=backend ;;
  fastapi) ENV_KEY=FASTAPI_IMAGE; SERVICE=ai ;;
  crawler) ENV_KEY=CRAWLER_IMAGE; SERVICE=crawler ;;
  *) echo "Usage: $0 <nextjs|spring|fastapi|crawler> <image@sha256:digest>" >&2; exit 2 ;;
esac

[[ "$IMAGE" =~ ^[0-9]{12}\.dkr\.ecr\.[a-z0-9-]+\.amazonaws\.com/lookddak-dev-${SERVICE_KEY}@sha256:[a-f0-9]{64}$ ]] \
  || { echo "Invalid image reference: ${IMAGE}" >&2; exit 2; }

cd "$APP_DIR"
exec 9>"${APP_DIR}/.deploy.lock"
flock -w 600 9 || { echo "Another deployment is still running" >&2; exit 1; }

PREVIOUS="$(awk -F= -v k="$ENV_KEY" '$1 == k {print substr($0, index($0, "=") + 1)}' "$DEPLOY_ENV")"
[[ -n "$PREVIOUS" ]] || { echo "${ENV_KEY} is missing in ${DEPLOY_ENV}" >&2; exit 1; }
echo "${SERVICE}: ${PREVIOUS} -> ${IMAGE}"

set_image() {
  local tmp
  tmp="$(mktemp "${DEPLOY_ENV}.XXXXXX")"
  awk -F= -v k="$ENV_KEY" -v v="$1" 'BEGIN{OFS="="} $1 == k {print k, v; next} {print}' "$DEPLOY_ENV" >"$tmp"
  chmod 0644 "$tmp"
  mv "$tmp" "$DEPLOY_ENV"
  "${APP_DIR}/scripts/load-parameters.sh"
}

wait_healthy() {
  local deadline=$((SECONDS + HEALTH_TIMEOUT_SECONDS)) status
  while ((SECONDS < deadline)); do
    status="$(docker inspect -f '{{.State.Health.Status}}' "lookddak-${SERVICE}" 2>/dev/null || echo missing)"
    [[ "$status" == "healthy" ]] && return 0
    sleep 5
  done
  echo "${SERVICE} did not become healthy within ${HEALTH_TIMEOUT_SECONDS}s (last: ${status})" >&2
  return 1
}

start_service() {
  docker compose --env-file .env pull --quiet "$SERVICE"
  if [[ "$SERVICE" == "crawler" ]]; then
    return 0 # batch profile: 다음 수동 실행부터 새 이미지를 쓴다.
  fi
  docker compose --env-file .env up -d --no-deps "$SERVICE"
  wait_healthy
}

REGISTRY="${IMAGE%%/*}"
REGION="$(cut -d. -f4 <<<"$REGISTRY")"
aws ecr get-login-password --region "$REGION" \
  | docker login --username AWS --password-stdin "$REGISTRY" >/dev/null

set_image "$IMAGE"
if start_service; then
  echo "Deployed ${SERVICE} ${IMAGE}"
  docker compose --env-file .env ps "$SERVICE"
  exit 0
fi

echo "Rolling back ${SERVICE} to ${PREVIOUS}" >&2
docker logs --tail 50 "lookddak-${SERVICE}" >&2 || true
set_image "$PREVIOUS"
start_service || echo "Rollback also failed for ${SERVICE}" >&2
exit 1
