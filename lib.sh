#!/usr/bin/env bash
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
    sed -i "s|^${key}=.*|${key}=${value}|" .env
  else
    printf '%s=%s\n' "$key" "$value" >> .env
  fi
}
