#!/usr/bin/env bash
# Safely update Nextcloud + MariaDB + Collabora (+ Redis if enabled).
# Safe to run while containers are up. Does NOT wipe data/ or regenerate DB passwords.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"
# shellcheck source=lib.sh
source "${ROOT}/lib.sh"

need docker
docker compose version >/dev/null

if [[ ! -f .env ]]; then
  echo "No .env found. Run ./install.sh first." >&2
  exit 1
fi

refuse_legacy_nextcloud_data
load_env

echo "==> Pulling newer images..."
compose pull
echo "==> Recreating containers if images/config changed (brief downtime per service)..."
compose up -d --remove-orphans
wait_for_db
wait_for_redis
echo "==> Status:"
compose ps
echo "==> Removing dangling (untagged) images only — not other projects' images..."
docker image prune -f

echo
echo "Update finished. data/ and .env credentials were left untouched."
if redis_enabled; then
  echo "Redis is enabled (ENABLE_REDIS=yes)."
fi
echo "Optional checks:"
echo "  ./verify-office.sh"
echo "  ./configure-office.sh   # only if Office URLs/IPs changed"
