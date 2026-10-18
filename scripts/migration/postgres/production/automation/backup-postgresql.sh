#!/usr/bin/env bash
# PostgreSQL globals와 custom-format dump를 생성해 운영 전용 S3 경로에 업로드한다.
set -Eeuo pipefail
set +x

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common-functions.sh
source "${ROOT}/common-functions.sh"

RUN_ID="${1:-}"
require_run_id "$RUN_ID"
require_root
require_commands aws docker flock mktemp sha256sum
acquire_migration_lock
start_run_log "$RUN_ID" backup

tmp_dir="$(mktemp -d /tmp/lookddak-pg-backup.XXXXXX)"
cleanup() {
  case "$tmp_dir" in
    /tmp/lookddak-pg-backup.*) rm -rf -- "$tmp_dir" ;;
    *) log "임시 백업 경로가 예상 형식이 아니므로 삭제하지 않습니다: $tmp_dir" ;;
  esac
}
trap cleanup EXIT

require_healthy lookddak-postgresql
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
object_prefix="${BACKUP_PREFIX}/${timestamp}"
dump_file="${tmp_dir}/lookddak_ai_${timestamp}.dump"
globals_file="${tmp_dir}/globals_${timestamp}.sql"

log "BACKUP_STARTED object_prefix=$object_prefix"
docker exec lookddak-postgresql sh -c \
  'exec pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" --format=custom --compress=6 --no-owner --no-acl' \
  > "$dump_file"
docker exec lookddak-postgresql sh -c \
  'exec pg_dumpall -U "$POSTGRES_USER" --globals-only --no-role-passwords' \
  > "$globals_file"

test -s "$dump_file"
test -s "$globals_file"
sha256sum "$dump_file" "$globals_file" > "${tmp_dir}/SHA256SUMS"

for file in "$dump_file" "$globals_file" "${tmp_dir}/SHA256SUMS"; do
  aws s3 cp "$file" "s3://${BACKUP_BUCKET}/${object_prefix}/$(basename "$file")" \
    --region "$AWS_REGION" \
    --only-show-errors \
    --server-side-encryption aws:kms \
    --ssekms-key-id alias/lookddak-prod-postgresql-backup
done

aws s3api head-object \
  --region "$AWS_REGION" \
  --bucket "$BACKUP_BUCKET" \
  --key "${object_prefix}/$(basename "$dump_file")" \
  --query '{Length:ContentLength,Modified:LastModified,Encryption:ServerSideEncryption,KmsKey:SSEKMSKeyId}' \
  --output json

log "BACKUP_SUCCEEDED object_prefix=$object_prefix"
