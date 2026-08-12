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

refuse_legacy_nextcloud_data() {
  if [[ "${I_UNDERSTAND_THIS_IS_A_FRESH_INSTALL:-}" == "yes" ]]; then
    echo "Override set: I_UNDERSTAND_THIS_IS_A_FRESH_INSTALL=yes — continuing."
    return 0
  fi
  local reason=""
  # LinuxServer Nextcloud often used ./data/config → /config
  if [[ -d data/config/www ]] || [[ -f data/config/www/index.php ]] || [[ -d data/config/nginx ]]; then
    reason="LinuxServer-style Nextcloud data under data/config/"
  fi
  if [[ -f data/html/config/config.php ]] && grep -Eq "['\"]dbtype['\"]\s*=>\s*['\"]sqlite['\"]" data/html/config/config.php; then
    reason="existing Nextcloud install using SQLite (data/html/config/config.php)"
  fi
  # Official image already installed without MariaDB data dir from this repo's MariaDB layout
  if [[ -f data/html/config/config.php ]] && [[ ! -d data/db/mysql ]] && [[ ! -f data/db/ibdata1 ]]; then
    if grep -Eq "['\"]dbtype['\"]\s*=>\s*['\"]sqlite['\"]" data/html/config/config.php 2>/dev/null; then
      reason="SQLite Nextcloud without MariaDB data/"
    fi
  fi
  if [[ -n "${reason}" ]]; then
    cat <<EOF >&2
Refusing to start: detected legacy data (${reason}).

git pull alone is safe. Re-running install/compose with MariaDB is NOT an
automatic migration and can leave you with a broken or mixed setup.

See BREAKING-CHANGES.md

Options:
  1) Keep your current containers running (do nothing).
  2) Backup, move data/ aside, install fresh on MariaDB.
  3) Only if you accept a fresh install:
       I_UNDERSTAND_THIS_IS_A_FRESH_INSTALL=yes ./install.sh
EOF
    exit 1
  fi
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
