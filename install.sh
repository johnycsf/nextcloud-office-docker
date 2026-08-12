#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"
# shellcheck source=lib.sh
source "${ROOT}/lib.sh"

parse_install_args "$@"
if [[ "${SHOW_HELP}" -eq 1 ]]; then
  print_install_help
  exit 0
fi

need docker
docker compose version >/dev/null

if [[ ! -f .env ]]; then
  cp .env.example .env
  echo "Created .env from .env.example"
fi

refuse_legacy_nextcloud_data
apply_redis_preference
ensure_db_passwords
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

mkdir -p data/html data/db
echo "Pulling images (Collabora is large)..."
compose pull
compose up -d

wait_for_db
wait_for_redis

echo
if redis_enabled; then
  echo "Containers are starting with MariaDB + Redis (not SQLite)."
else
  echo "Containers are starting with MariaDB (not SQLite). Redis skipped (pass --redis to enable)."
fi
load_env
echo "1) Open http://${NEXTCLOUD_HOST}/"
echo "2) Create your Nextcloud admin account (database fields are already configured)"
echo "3) This script will finish Office setup automatically"
echo
"${ROOT}/configure-office.sh"
