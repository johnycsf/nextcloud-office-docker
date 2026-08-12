#!/usr/bin/env bash
# Shared helpers for nextcloud-office-docker.
# shellcheck shell=bash
need() {
  command -v "$1" >/dev/null 2>&1 || { echo "Missing required command: $1" >&2; exit 1; }
}

escape_regex_dots() {
  # shellcheck disable=SC2001
  printf '%s' "$1" | sed 's/\./\\\\./g'
}

load_env() {
  if [[ -f .env ]]; then
    set -a
    # shellcheck disable=SC1091
    source .env
    set +a
  fi
}

detect_host_ip() {
  hostname -I 2>/dev/null | awk '{print $1}'
}

gen_password() {
  # URL/shell-safe-ish password for .env
  openssl rand -base64 32 | tr -d '\n/+=\n' | head -c 32
}

ensure_db_passwords() {
  need openssl
  load_env
  local changed=0
  if [[ -z "${MYSQL_PASSWORD:-}" || "${MYSQL_PASSWORD}" == changeme* ]]; then
    set_env_var MYSQL_PASSWORD "$(gen_password)"
    changed=1
  fi
  if [[ -z "${MYSQL_ROOT_PASSWORD:-}" || "${MYSQL_ROOT_PASSWORD}" == changeme* ]]; then
    set_env_var MYSQL_ROOT_PASSWORD "$(gen_password)"
    changed=1
  fi
  if [[ "${changed}" -eq 1 ]]; then
    echo "Generated MariaDB passwords in .env (keep this file private)."
  fi
  load_env
}

# Official Nextcloud image: occ via php as www-data
occ() {
  docker compose exec -u www-data -T nextcloud php occ "$@"
}

nc_fetch() {
  local url="$1"
  docker compose exec -T nextcloud php -r 'echo @file_get_contents($argv[1]);' "$url"
}

set_env_var() {
  local key="$1" value="$2"
  if grep -q "^${key}=" .env; then
    # Escape & for sed replacement
    local escaped="${value//&/\\&}"
    sed -i "s|^${key}=.*|${key}=${escaped}|" .env
  else
    printf '%s=%s\n' "$key" "$value" >> .env
  fi
}

wait_for_db() {
  echo "Waiting for MariaDB to become healthy..."
  local i
  for i in $(seq 1 60); do
    if docker compose exec -T db healthcheck.sh --connect --innodb_initialized >/dev/null 2>&1; then
      echo "MariaDB is ready."
      return 0
    fi
    sleep 2
  done
  echo "MariaDB did not become ready in time." >&2
  docker compose logs --tail=50 db >&2 || true
  exit 1
}
