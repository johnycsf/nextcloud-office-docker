#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
# shellcheck source=scripts/deps.sh
source "${ROOT}/scripts/deps.sh"
# shellcheck source=scripts/lib.sh
source "${ROOT}/scripts/lib.sh"

need_container_engine
load_env

FAIL=0
pass() { echo "  PASS  $*"; }
fail() { echo "  FAIL  $*" >&2; FAIL=1; }

echo "=== Office verification ==="

NC_HOST="${NEXTCLOUD_HOST:-}"
CO_HOST="${COLLABORA_HOST:-$NC_HOST}"
NC_PORT="${NEXTCLOUD_PORT:-8082}"
CO_PORT="${COLLABORA_PORT:-9980}"
COLLABORA_PUBLIC_URL="http://${CO_HOST}:${CO_PORT}"
COLLABORA_INTERNAL_URL="http://collabora:9980"
NC_URL="http://${NC_HOST}"
if [[ "${NC_PORT}" != "80" ]]; then
  NC_URL="http://${NC_HOST}:${NC_PORT}"
fi

if nc_fetch "${COLLABORA_INTERNAL_URL}/hosting/discovery" | grep -q urlsrc; then
  pass "Nextcloud can reach Collabora on the Docker network"
else
  fail "Nextcloud cannot reach ${COLLABORA_INTERNAL_URL}/hosting/discovery"
fi

if nc_fetch "${COLLABORA_PUBLIC_URL}/hosting/discovery" | grep -q urlsrc; then
  pass "Collabora public discovery responds"
else
  fail "Collabora public discovery failed at ${COLLABORA_PUBLIC_URL}"
fi

if ! occ status 2>/dev/null | grep -q 'installed: true'; then
  fail "Nextcloud is not installed yet"
  exit 1
fi
pass "Nextcloud is installed"

DBTYPE="$(occ config:system:get dbtype 2>/dev/null || true)"
if [[ "${DBTYPE}" == "mysql" ]]; then
  pass "Database is MariaDB/MySQL (dbtype=${DBTYPE})"
else
  fail "Expected MariaDB/MySQL (dbtype=mysql), got: ${DBTYPE:-empty} - use a fresh data/ volume with MYSQL_* set"
fi

if compose exec -T db healthcheck.sh --connect --innodb_initialized >/dev/null 2>&1; then
  pass "MariaDB healthcheck is OK"
else
  fail "MariaDB healthcheck failed"
fi

if redis_enabled; then
  if compose exec -T redis redis-cli ping 2>/dev/null | grep -q PONG; then
    pass "Redis responds to PING"
  else
    fail "Redis enabled but not responding (ENABLE_REDIS=yes)"
  fi
  # REDIS_HOST is set via compose overlay for the nextcloud service
  if compose exec -T nextcloud /bin/sh -c 'printenv REDIS_HOST' 2>/dev/null | grep -qx 'redis'; then
    pass "Nextcloud has REDIS_HOST=redis"
  else
    fail "Nextcloud REDIS_HOST is not redis - recreate with ./manage.sh install --include-redis"
  fi
else
  pass "Redis not enabled (optional; use ./manage.sh install --include-redis)"
fi

WOPI="$(occ config:app:get richdocuments wopi_url 2>/dev/null || true)"
PUB="$(occ config:app:get richdocuments public_wopi_url 2>/dev/null || true)"
[[ "$WOPI" == "$COLLABORA_INTERNAL_URL" ]] && pass "wopi_url is in-compose ($WOPI)" || fail "wopi_url expected $COLLABORA_INTERNAL_URL (got ${WOPI:-empty})"
[[ "$PUB" == "$COLLABORA_PUBLIC_URL" ]] && pass "public_wopi_url is browser-facing ($PUB)" || fail "public_wopi_url expected $COLLABORA_PUBLIC_URL (got ${PUB:-empty})"

echo
if [[ "$FAIL" -eq 0 ]]; then
  echo "All checks passed. Manual check: open ${NC_URL} -> + New -> Document"
  exit 0
fi
echo "One or more checks failed. Re-run ./scripts/configure-office.sh" >&2
exit 1
