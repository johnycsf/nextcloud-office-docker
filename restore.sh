#!/usr/bin/env bash
# Restore Nextcloud Docker (files + MariaDB) from a backups/update-* snapshot.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"
# shellcheck source=lib.sh
source "${ROOT}/lib.sh"

need docker
docker compose version >/dev/null

if [[ ! -d backups ]]; then
  echo "No backups/ directory found. Run ./update.sh at least once first." >&2
  exit 1
fi

mapfile -t DIRS < <(ls -1dt backups/update-* 2>/dev/null || true)
if ((${#DIRS[@]} == 0)); then
  echo "No backups/update-* snapshots found." >&2
  exit 1
fi

echo "Available backups (newest first):"
i=1
for d in "${DIRS[@]}"; do
  size="$(du -sh "$d" 2>/dev/null | awk '{print $1}')"
  extras=""
  [[ -f "$d/html.tar.gz" ]] && extras+=" html"
  [[ -f "$d/nextcloud-db.sql" ]] && extras+=" sql"
  [[ -f "$d/db-datadir.tar.gz" ]] && extras+=" dbdir"
  echo "  ${i}) ${d}  (${size}${extras})"
  i=$((i + 1))
done

choice=""
if [[ -t 0 ]]; then
  read -r -p "Restore which backup number? [1] " choice || true
else
  echo "Non-interactive: use ./restore.sh with a TTY to choose a backup." >&2
  exit 1
fi
choice="${choice:-1}"
if ! [[ "${choice}" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#DIRS[@]} )); then
  echo "Invalid selection." >&2
  exit 1
fi
SRC="${DIRS[$((choice - 1))]}"

if [[ ! -f "${SRC}/html.tar.gz" ]]; then
  echo "Backup ${SRC} is missing html.tar.gz" >&2
  exit 1
fi

echo
echo "This will STOP the stack and REPLACE Nextcloud files (+ DB if SQL dump exists)."
echo "Source: ${SRC}"
read -r -p "Type 'restore' to continue: " confirm || true
if [[ "${confirm}" != "restore" ]]; then
  echo "Aborted."
  exit 1
fi

load_env
echo "==> Stopping stack..."
compose down

echo "==> Restoring config / files..."
[[ -f "${SRC}/.env" ]] && cp -a "${SRC}/.env" .env
load_env
rm -rf data/html
mkdir -p data/html
tar -C data/html -xzf "${SRC}/html.tar.gz"

if [[ -f "${SRC}/nextcloud-db.sql" ]]; then
  echo "==> Starting MariaDB only..."
  compose up -d db
  wait_for_db
  echo "==> Importing SQL dump..."
  compose exec -T db mariadb \
    -u"${MYSQL_USER:-nextcloud}" \
    -p"${MYSQL_PASSWORD}" \
    "${MYSQL_DATABASE:-nextcloud}" \
    <"${SRC}/nextcloud-db.sql"
elif [[ -f "${SRC}/db-datadir.tar.gz" ]]; then
  echo "==> No SQL dump — restoring data/db from archive (stack must stay down)..."
  rm -rf data/db
  mkdir -p data/db
  tar -C data/db -xzf "${SRC}/db-datadir.tar.gz"
else
  echo "Warning: no nextcloud-db.sql or db-datadir.tar.gz — files restored only." >&2
fi

echo "==> Starting full stack..."
compose up -d
wait_for_db
wait_for_redis
compose ps
echo
echo "Restore finished from ${SRC}."
echo "Optional: ./verify-office.sh"
