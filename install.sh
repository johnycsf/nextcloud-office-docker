#!/usr/bin/env bash
# Install Nextcloud + Collabora + MariaDB with Docker Compose (interactive).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"
# shellcheck source=deps.sh
source "${ROOT}/deps.sh"
# shellcheck source=lib.sh
source "${ROOT}/lib.sh"

parse_install_args "$@"
if [[ "${SHOW_HELP}" -eq 1 ]]; then
  print_install_help
  exit 0
fi

ui_banner "Nextcloud + Office" "Docker Compose · official Nextcloud, MariaDB, Collabora"
ui_steps_init 5

ui_step "Checking host dependencies"
ensure_host_deps docker

ui_step "Preparing configuration"
if [[ ! -f .env ]]; then
  cp .env.example .env
  ui_ok "Created .env from .env.example"
else
  ui_ok "Using existing .env"
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
    ui_ok "Detected host IP ${IP} and wrote it into .env"
  fi
fi

mkdir -p data/html data/db

ui_step "Pulling images (Collabora is large)"
ui_run "compose pull" compose pull

ui_step "Starting containers"
ui_run "compose up -d" compose up -d

ui_step "Waiting for database services"
wait_for_db
wait_for_redis
ui_ok "Database layer is ready"

echo
if redis_enabled; then
  ui_ok "Stack: MariaDB + Redis + Nextcloud + Collabora"
else
  ui_ok "Stack: MariaDB + Nextcloud + Collabora (Redis skipped — pass --include-redis to enable)"
fi
load_env
ui_info "1) Open ${UI_BOLD}http://${NEXTCLOUD_HOST}/${UI_RESET}"
ui_info "2) Create your Nextcloud admin account"
ui_info "3) Finishing Office setup automatically…"
echo
"${ROOT}/configure-office.sh"
