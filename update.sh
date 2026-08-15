#!/usr/bin/env bash
# Safely update Nextcloud + MariaDB + Collabora (+ Redis if enabled).
# Creates a local rollback backup first, then asks whether to keep it.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"
# shellcheck source=lib.sh
source "${ROOT}/lib.sh"

KEEP_FILE=".backup-keep-count"
DEFAULT_KEEP=3

print_offsite_tip() {
  cat <<'EOF'

Tip: Local backups under backups/ can fill your disk over time.
Copy important snapshots to an external drive, NAS, or cloud
(rclone, Backblaze B2, S3, Nextcloud, etc.), then keep fewer copies here.
Restore later with: ./restore.sh
EOF
}

prune_old_backups() {
  local keep="$1"
  mkdir -p backups
  mapfile -t dirs < <(ls -1dt backups/update-* 2>/dev/null || true)
  local total="${#dirs[@]}"
  if (( total <= keep )); then
    echo "Backup retention: keeping all ${total} local snapshot(s) (limit ${keep})."
    return 0
  fi
  local i
  for (( i = keep; i < total; i++ )); do
    echo "Removing old backup: ${dirs[$i]}"
    rm -rf "${dirs[$i]}"
  done
  echo "Backup retention: kept ${keep} newest snapshot(s); removed $((total - keep)) older one(s)."
}

ask_backup_retention() {
  local dir="$1"
  if [[ ! -d "${dir}" ]]; then
    return 0
  fi
  if [[ ! -t 0 ]]; then
    echo "No interactive terminal — keeping backup at ${dir}"
    local keep="${DEFAULT_KEEP}"
    [[ -f "${KEEP_FILE}" ]] && keep="$(tr -dc '0-9' <"${KEEP_FILE}" || true)"
    [[ -z "${keep}" ]] && keep="${DEFAULT_KEEP}"
    echo "${keep}" >"${KEEP_FILE}"
    prune_old_backups "${keep}"
    print_offsite_tip
    return 0
  fi
  echo
  local reply=""
  read -r -p "Update succeeded. Keep rollback backup at ${dir}? [Y/n] " reply || true
  case "${reply:-Y}" in
    n|N|no|NO)
      rm -rf "${dir}"
      rmdir backups 2>/dev/null || true
      echo "Backup deleted."
      ;;
    *)
      echo "Backup kept."
      local default="${DEFAULT_KEEP}"
      [[ -f "${KEEP_FILE}" ]] && default="$(tr -dc '0-9' <"${KEEP_FILE}" || true)"
      [[ -z "${default}" ]] && default="${DEFAULT_KEEP}"
      local keep=""
      read -r -p "How many local update backups should we keep on this disk? [${default}] " keep || true
      keep="$(printf '%s' "${keep:-$default}" | tr -dc '0-9')"
      [[ -z "${keep}" || "${keep}" -lt 1 ]] && keep="${default}"
      echo "${keep}" >"${KEEP_FILE}"
      prune_old_backups "${keep}"
      print_offsite_tip
      echo "  This snapshot: ${dir}"
      echo "  Manual restore: ./restore.sh"
      ;;
  esac
}



create_backup() {
  BACKUP_DIR="backups/update-$(date +%Y%m%d-%H%M%S)"
  mkdir -p "${BACKUP_DIR}"
  echo "==> Creating rollback backup in ${BACKUP_DIR} ..."
  [[ -f .env ]] && cp -a .env "${BACKUP_DIR}/"
  [[ -f docker-compose.yml ]] && cp -a docker-compose.yml "${BACKUP_DIR}/"
  [[ -f docker-compose.redis.yml ]] && cp -a docker-compose.redis.yml "${BACKUP_DIR}/"

  load_env
  if compose ps -q db 2>/dev/null | grep -q .; then
    echo "    Dumping MariaDB..."
    compose exec -T db mariadb-dump \
      -u"${MYSQL_USER:-nextcloud}" \
      -p"${MYSQL_PASSWORD}" \
      --single-transaction \
      --routines \
      "${MYSQL_DATABASE:-nextcloud}" \
      >"${BACKUP_DIR}/nextcloud-db.sql" \
      || echo "    Warning: MariaDB dump failed (continuing with file backup)."
  fi

  if [[ -d data/html ]]; then
    echo "    Archiving Nextcloud files (data/html)..."
    tar -C data/html -czf "${BACKUP_DIR}/html.tar.gz" .
  fi
  if [[ -d data/db ]]; then
    echo "    Archiving MariaDB data dir (data/db) as extra safety..."
    tar -C data/db -czf "${BACKUP_DIR}/db-datadir.tar.gz" . || true
  fi

  cat >"${BACKUP_DIR}/RESTORE.txt" <<EOF
Prefer: ./restore.sh

Manual Nextcloud Docker rollback:

  cd $(pwd)
  docker compose down
  cp -a ${BACKUP_DIR}/.env .env
  rm -rf data/html
  mkdir -p data/html
  tar -C data/html -xzf ${BACKUP_DIR}/html.tar.gz
  # Start DB only, then import SQL, then bring full stack up:
  #   docker compose up -d db
  #   docker compose exec -T db mariadb -u\$MYSQL_USER -p\$MYSQL_PASSWORD \$MYSQL_DATABASE < ${BACKUP_DIR}/nextcloud-db.sql
  #   docker compose up -d
  # Or restore data/db from db-datadir.tar.gz with the stack fully stopped.
EOF
  echo "Backup ready: ${BACKUP_DIR}"
}

need docker
docker compose version >/dev/null

if [[ ! -f .env ]]; then
  echo "No .env found. Run ./install.sh first." >&2
  exit 1
fi

refuse_legacy_nextcloud_data
load_env
create_backup

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
echo "Update finished. Live data/ was left in place (backup is a point-in-time copy)."
if redis_enabled; then
  echo "Redis is enabled (ENABLE_REDIS=yes)."
fi
echo "Optional checks:"
echo "  ./verify-office.sh"
echo "  ./configure-office.sh   # only if Office URLs/IPs changed"
ask_backup_retention "${BACKUP_DIR}"
