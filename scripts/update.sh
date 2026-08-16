#!/usr/bin/env bash
# Safely update Nextcloud + MariaDB + Collabora (+ Redis if enabled).
# Creates a local rollback backup first, then asks whether to keep it.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
# shellcheck source=scripts/lib.sh
source "${ROOT}/scripts/lib.sh"


KEEP_FILE=".backup-keep-count"
DEFAULT_KEEP=3
BACKUP_ROOT="${ROOT}/backups"

need() { command -v "$1" >/dev/null || { echo "Missing: $1" >&2; exit 1; }; }

print_offsite_tip() {
  cat <<'EOF'

Tip: Local backups under backups/ can fill your disk over time.
Copy important snapshots to an external drive, NAS, or cloud
(rclone, Backblaze B2, S3, Nextcloud, etc.), then keep fewer copies here.
Restore later with:
  ./manage.sh backup --restore --from ./backups
  ./manage.sh backup --restore --from /mnt/usb/my-backups
EOF
}

prune_old_backups() {
  local keep="$1"
  mkdir -p "${BACKUP_ROOT}/snapshots"
  mapfile -t dirs < <(ls -1dt "${BACKUP_ROOT}"/snapshots/* 2>/dev/null || true)
  # Also prune any leftover legacy update-* tarball folders from older scripts
  mapfile -t legacy < <(ls -1dt "${BACKUP_ROOT}"/update-* 2>/dev/null || true)
  local total="${#dirs[@]}"
  if (( total > keep )); then
    local i
    for (( i = keep; i < total; i++ )); do
      echo "Removing old snapshot: ${dirs[$i]}"
      rm -rf "${dirs[$i]}"
    done
    echo "Backup retention: kept ${keep} newest snapshot(s); removed $((total - keep)) older one(s)."
  else
    echo "Backup retention: keeping all ${total} snapshot(s) (limit ${keep})."
  fi
  if ((${#legacy[@]} > 0)); then
    echo "Note: found ${#legacy[@]} legacy backups/update-* folder(s)."
    echo "  Restore those manually via their RESTORE.txt, or delete them to free space."
  fi
  # Refresh latest symlink if needed
  if [[ -d "${BACKUP_ROOT}/snapshots" ]]; then
    local newest
    newest="$(ls -1dt "${BACKUP_ROOT}"/snapshots/* 2>/dev/null | head -1 || true)"
    if [[ -n "$newest" ]]; then
      ln -sfn "snapshots/$(basename "$newest")" "${BACKUP_ROOT}/latest"
    fi
  fi
}

ask_backup_retention() {
  local dir="$1"
  if [[ -z "${dir}" || ! -e "${dir}" ]]; then
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
      # fix latest pointer
      if [[ -L "${BACKUP_ROOT}/latest" ]]; then
        local cur
        cur="$(readlink -f "${BACKUP_ROOT}/latest" 2>/dev/null || true)"
        if [[ "$cur" == "$dir" ]]; then
          rm -f "${BACKUP_ROOT}/latest"
          local newest
          newest="$(ls -1dt "${BACKUP_ROOT}"/snapshots/* 2>/dev/null | head -1 || true)"
          [[ -n "$newest" ]] && ln -sfn "snapshots/$(basename "$newest")" "${BACKUP_ROOT}/latest"
        fi
      fi
      rmdir "${BACKUP_ROOT}/snapshots" 2>/dev/null || true
      rmdir "${BACKUP_ROOT}" 2>/dev/null || true
      echo "Backup deleted."
      ;;
    *)
      echo "Backup kept."
      local default="${DEFAULT_KEEP}"
      [[ -f "${KEEP_FILE}" ]] && default="$(tr -dc '0-9' <"${KEEP_FILE}" || true)"
      [[ -z "${default}" ]] && default="${DEFAULT_KEEP}"
      local keep=""
      read -r -p "How many local backups should we keep on this disk? [${default}] " keep || true
      keep="$(printf '%s' "${keep:-$default}" | tr -dc '0-9')"
      [[ -z "${keep}" || "${keep}" -lt 1 ]] && keep="${default}"
      echo "${keep}" >"${KEEP_FILE}"
      prune_old_backups "${keep}"
      print_offsite_tip
      echo "  This snapshot: ${dir}"
      echo "  Manual restore: ./manage.sh backup --restore --from ./backups"
      ;;
  esac
}

create_backup() {
  if [[ ! -x "${ROOT}/scripts/backup.sh" ]]; then
    echo "Missing executable backup.sh (required for pre-update snapshots)." >&2
    exit 1
  fi
  local keep="${DEFAULT_KEEP}"
  [[ -f "${KEEP_FILE}" ]] && keep="$(tr -dc '0-9' <"${KEEP_FILE}" || true)"
  [[ -z "${keep}" ]] && keep="${DEFAULT_KEEP}"
  echo "==> Pre-update snapshot via ./manage.sh backup --dest ${BACKUP_ROOT} ..."
  "${ROOT}/scripts/backup.sh" --dest "${BACKUP_ROOT}" --keep "${keep}"
  if [[ -L "${BACKUP_ROOT}/latest" ]]; then
    BACKUP_DIR="$(readlink -f "${BACKUP_ROOT}/latest")"
  else
    BACKUP_DIR="$(ls -1dt "${BACKUP_ROOT}"/snapshots/* 2>/dev/null | head -1 || true)"
  fi
  if [[ -z "${BACKUP_DIR}" || ! -d "${BACKUP_DIR}" ]]; then
    echo "Pre-update backup did not produce a snapshot." >&2
    exit 1
  fi
  echo "Backup ready: ${BACKUP_DIR}"
}


need docker
docker compose version >/dev/null

if [[ ! -f .env ]]; then
  echo "No .env found. Run ./manage.sh first." >&2
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
echo "  ./scripts/verify-office.sh"
echo "  ./scripts/configure-office.sh   # only if Office URLs/IPs changed"
ask_backup_retention "${BACKUP_DIR}"
