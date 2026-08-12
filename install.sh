#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"
# shellcheck source=lib.sh
source "${ROOT}/lib.sh"

need docker
docker compose version >/dev/null

if [[ ! -f .env ]]; then
  cp .env.example .env
  echo "Created .env from .env.example"
fi

load_env
IP="$(detect_host_ip || true)"
if [[ -n "${IP}" ]]; then
  if grep -q 'NEXTCLOUD_HOST=192.168.1.50' .env; then
    set_env_var NEXTCLOUD_HOST "$IP"
    set_env_var COLLABORA_HOST "$IP"
    set_env_var ALIASGROUP1 "http://${IP}:80"
    set_env_var COLLABORA_DOMAIN_REGEX "$(escape_regex_dots "$IP")"
    set_env_var COLLABORA_SERVER_NAME "${IP}:${COLLABORA_PORT:-9980}"
    echo "Detected host IP ${IP} and wrote it into .env (edit if wrong)."
  fi
fi

mkdir -p data/html
echo "Pulling images (Collabora is large)..."
docker compose pull
docker compose up -d

echo
echo "Containers are starting."
load_env
echo "1) Open http://${NEXTCLOUD_HOST}/"
echo "2) Create your Nextcloud admin account"
echo "3) This script will finish Office setup automatically"
echo
"${ROOT}/configure-office.sh"
