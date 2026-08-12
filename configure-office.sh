#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"
# shellcheck source=lib.sh
source "${ROOT}/lib.sh"

need docker
docker compose version >/dev/null
load_env

NC_HOST="${NEXTCLOUD_HOST:-$(detect_host_ip)}"
CO_HOST="${COLLABORA_HOST:-$NC_HOST}"
NC_PORT="${NEXTCLOUD_PORT:-80}"
CO_PORT="${COLLABORA_PORT:-9980}"

if [[ -z "${NC_HOST}" ]]; then
  echo "Set NEXTCLOUD_HOST in .env (your LAN IP or hostname)." >&2
  exit 1
fi

NC_URL="http://${NC_HOST}"
if [[ "${NC_PORT}" != "80" ]]; then
  NC_URL="http://${NC_HOST}:${NC_PORT}"
fi
COLLABORA_PUBLIC_URL="http://${CO_HOST}:${CO_PORT}"
COLLABORA_INTERNAL_URL="http://collabora:9980"
DOMAIN_REGEX="$(escape_regex_dots "${NC_HOST}")"
ALIAS="http://${NC_HOST}:80"

echo "Nextcloud URL           : ${NC_URL}"
echo "Collabora (browser)    : ${COLLABORA_PUBLIC_URL}"
echo "Collabora (compose)    : ${COLLABORA_INTERNAL_URL}"

set_env_var NEXTCLOUD_HOST "${NC_HOST}"
set_env_var COLLABORA_HOST "${CO_HOST}"
set_env_var ALIASGROUP1 "${ALIAS}"
set_env_var COLLABORA_DOMAIN_REGEX "${DOMAIN_REGEX}"
set_env_var COLLABORA_SERVER_NAME "${CO_HOST}:${CO_PORT}"

echo "Recreating Collabora with updated allow-list..."
compose up -d collabora

echo "Waiting until Nextcloud setup wizard is finished..."
echo "Open: ${NC_URL}"
echo "(Database is MariaDB — create the admin account only; DB fields are auto-configured.)"
for i in $(seq 1 180); do
  if occ status 2>/dev/null | grep -q 'installed: true'; then
    echo "Nextcloud is installed."
    break
  fi
  if [[ "$i" -eq 180 ]]; then
    echo "Timed out. Create the admin account, then re-run ./configure-office.sh" >&2
    exit 1
  fi
  sleep 5
done

echo "Configuring Nextcloud Office..."
occ config:system:set trusted_domains 1 --value="${NC_HOST}" >/dev/null
occ config:system:set overwrite.cli.url --value="${NC_URL}" >/dev/null
occ config:system:set overwriteprotocol --value="http" >/dev/null
occ config:system:set allow_local_remote_servers --type=boolean --value=true >/dev/null

occ app:disable richdocumentscode 2>/dev/null || true
occ app:disable richdocumentscode_arm64 2>/dev/null || true
occ app:install richdocuments 2>/dev/null || true
occ app:enable richdocuments

occ config:app:set richdocuments wopi_url --value="${COLLABORA_INTERNAL_URL}"
occ config:app:set richdocuments public_wopi_url --value="${COLLABORA_PUBLIC_URL}"
occ config:app:set richdocuments disable_certificate_verification --type=string --value="yes"
occ config:app:set richdocuments wopi_allowlist --value="0.0.0.0/0,::/0"
occ richdocuments:activate-config >/dev/null 2>&1 || true

"${ROOT}/verify-office.sh"

cat <<MSG

Office editing is configured.

Nextcloud:  ${NC_URL}
Collabora:  ${COLLABORA_PUBLIC_URL}/hosting/discovery

Try: + New → Document / Spreadsheet / Presentation

MSG
