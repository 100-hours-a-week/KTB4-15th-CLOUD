#!/usr/bin/env bash
# 원본 PG의 SCRAM 검증값만 런타임 인증 파일로 복사한다. DB 쓰기는 하지 않는다.
# userlist.txt는 Git에 넣지 않으며, 비밀번호/검증값을 stdout에 출력하지 않는다.
set -Eeuo pipefail

readonly APP_DIR="/opt/lookddak"
readonly AUTH_DIR="${APP_DIR}/pgbouncer"
readonly PGBOUNCER_IMAGE="edoburu/pgbouncer:v1.26.0-p0@sha256:b17551c776ef7e5769ef80b956d20f85e2fd25dd8912d31d58f782aad495b711"
auth_tmp=""

cleanup() {
  if [[ "$auth_tmp" == "${AUTH_DIR}/userlist.tmp."* && -f "$auth_tmp" ]]; then
    rm -f -- "$auth_tmp"
  fi
}
trap cleanup EXIT

[[ "$EUID" -eq 0 ]] || { printf 'root 권한으로 실행하세요.\n' >&2; exit 1; }
for required_command in docker install mktemp grep; do
  command -v "$required_command" >/dev/null || { printf '필수 명령 없음: %s\n' "$required_command" >&2; exit 1; }
done
docker inspect lookddak-postgresql >/dev/null
docker pull "$PGBOUNCER_IMAGE"
runtime_user="$(docker run --rm --network none --read-only --cap-drop ALL --entrypoint id "$PGBOUNCER_IMAGE" -un)"
[[ "$runtime_user" == "postgres" ]] || { printf '예상하지 못한 이미지 OS 사용자\n' >&2; exit 1; }
runtime_uid="$(docker run --rm --network none --read-only --cap-drop ALL --entrypoint id "$PGBOUNCER_IMAGE" -u)"
runtime_gid="$(docker run --rm --network none --read-only --cap-drop ALL --entrypoint id "$PGBOUNCER_IMAGE" -g)"
install -d -o "$runtime_uid" -g "$runtime_gid" -m 0750 "$AUTH_DIR"
auth_tmp="$(mktemp "${AUTH_DIR}/userlist.tmp.XXXXXX")"

docker exec -e 'PGOPTIONS=-c default_transaction_read_only=on' lookddak-postgresql sh -c 'psql -X -v ON_ERROR_STOP=1 -At -U "$POSTGRES_USER" -d "${POSTGRES_DB:-$POSTGRES_USER}" -c "SELECT chr(34) || rolname || chr(34) || chr(32) || chr(34) || rolpassword || chr(34) FROM pg_authid WHERE rolname = current_user AND rolcanlogin"' > "$auth_tmp"
[[ "$(wc -l < "$auth_tmp")" -eq 1 ]] || { printf '원본 앱 계정 검증값 조회 실패\n' >&2; exit 1; }
grep -q '^"lookddak_ai_app" "SCRAM-SHA-256\$' "$auth_tmp" || { printf '예상한 SCRAM 계정이 아닙니다.\n' >&2; exit 1; }
printf '"pgbouncer_admin" ""\n' >> "$auth_tmp"
install -o "$runtime_uid" -g "$runtime_gid" -m 0600 "$auth_tmp" "${AUTH_DIR}/userlist.txt"
printf 'PgBouncer 인증 파일 준비 완료: 앱 SCRAM + 내부 소켓 관리자, 평문 비밀번호 없음\n'
