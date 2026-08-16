#!/usr/bin/env bash
# Install Nextcloud + Collabora + MariaDB with Compose / Docker or Podman (interactive).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
# shellcheck source=scripts/deps.sh
source "${ROOT}/scripts/deps.sh"
# shellcheck source=scripts/lib.sh
source "${ROOT}/scripts/lib.sh"

parse_install_args "$@"
if [[ "${SHOW_HELP}" -eq 1 ]]; then
  print_install_help
  exit 0
fi

ui_steps_init 5
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
configure_container_engine
ui_banner "Nextcloud + Office" "$(compose_stack_subtitle "official Nextcloud, MariaDB, Collabora")"

ui_step "Checking host dependencies"
ensure_host_deps docker

configure_host_port NEXTCLOUD_PORT "Nextcloud HTTP" 80
configure_host_port COLLABORA_PORT "Collabora HTTP" 9980
load_env
IP="$(detect_host_ip || true)"
if [[ -n "${IP}" ]]; then
  set_env_var NEXTCLOUD_HOST "$IP"
  set_env_var COLLABORA_HOST "$IP"
  if [[ "${NEXTCLOUD_PORT}" == "80" ]]; then
    set_env_var ALIASGROUP1 "http://${IP}"
  else
    set_env_var ALIASGROUP1 "http://${IP}:${NEXTCLOUD_PORT}"
  fi
  set_env_var COLLABORA_DOMAIN_REGEX "$(escape_regex_dots "$IP")"
  set_env_var COLLABORA_SERVER_NAME "${IP}:${COLLABORA_PORT}"
  ui_ok "Host IP ${IP} + ports written into .env (Nextcloud ${NEXTCLOUD_PORT}, Collabora ${COLLABORA_PORT})"
fi

mkdir -p data/html data/db

ui_step "Pulling images (Collabora is large)"
ui_run "compose pull" compose pull

ui_step "Starting containers"
ui_run "compose up -d" compose up -d

ensure_host_owned_dir data/html data/db

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
if [[ "${NEXTCLOUD_PORT}" == "80" ]]; then
  ui_info "1) Open ${UI_BOLD}http://${NEXTCLOUD_HOST}/${UI_RESET}"
else
  ui_info "1) Open ${UI_BOLD}http://${NEXTCLOUD_HOST}:${NEXTCLOUD_PORT}/${UI_RESET}"
fi
ui_info "2) Create your Nextcloud admin account"
ui_info "3) Finishing Office setup automatically…"
echo
"${ROOT}/scripts/configure-office.sh"
