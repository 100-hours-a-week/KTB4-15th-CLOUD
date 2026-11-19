#!/usr/bin/env bash
set -Eeuo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run with sudo." >&2
  exit 1
fi

dnf install -y docker awscli python3
systemctl enable --now docker

install -d -m 0755 /usr/local/lib/docker/cli-plugins
curl -fsSL https://github.com/docker/compose/releases/download/v2.29.7/docker-compose-linux-aarch64 \
  -o /usr/local/lib/docker/cli-plugins/docker-compose
chmod 0755 /usr/local/lib/docker/cli-plugins/docker-compose

install -d -m 0755 \
  /srv/lookddak/data/mysql \
  /srv/lookddak/data/postgres \
  /srv/lookddak/certbot/conf \
  /srv/lookddak/certbot/www \
  /srv/lookddak/backups

docker --version
docker compose version
