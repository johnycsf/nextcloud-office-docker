#!/usr/bin/env bash
# Disaster-recovery backup/restore with incremental rsync snapshots.
# Restores files + MariaDB and runs Nextcloud occ repair/scan so a fresh host matches the backup.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"
# shellcheck source=lib.sh
source "${ROOT}/lib.sh"
STACK_ID="nextcloud-office-docker"

need_rsync() {
  command -v rsync >/dev/null 2>&1 || {
    echo "Missing: rsync (needed for incremental snapshots)." >&2
    exit 1
  }
}

usage() {
  cat <<EOF
Usage:
  ./backup.sh --dest /path/to/backup-root [--keep N]
  ./backup.sh --restore --from /path/to/backup-root-or-snapshot
  ./backup.sh --help

Disaster-recovery backups (separate from update.sh rollback tarballs).

  --dest DIR    Create a new incremental snapshot under DIR.
                Uses rsync hardlinks against the previous snapshot so
                unchanged files are not duplicated on disk.
  --keep N      After backup, keep only the newest N snapshots (default: no prune).
  --restore     Restore into this deployment from --from.
  --from PATH   Backup root (uses latest/) or a specific snapshots/TIMESTAMP dir.

Fresh-machine workflow:
  1) Install this stack on the new host (./install.sh) so runtime exists.
  2) ./backup.sh --restore --from /mnt/usb/my-backups
  3) Script replaces data/secrets and finishes app-specific repair (e.g. Nextcloud scan).
EOF
}

MODE=""
DEST=""
FROM=""
KEEP=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dest)
      [[ $# -ge 2 ]] || { echo "--dest needs a path" >&2; exit 1; }
      DEST="$2"; MODE="${MODE:-backup}"; shift 2 ;;
    --from)
      [[ $# -ge 2 ]] || { echo "--from needs a path" >&2; exit 1; }
      FROM="$2"; shift 2 ;;
    --restore)
      MODE="restore"; shift ;;
    --keep)
      [[ $# -ge 2 ]] || { echo "--keep needs a number" >&2; exit 1; }
      KEEP="$2"; shift 2 ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
done

stamp_now() { date +%Y%m%d-%H%M%S; }

resolve_snapshot_dir() {
  local path="$1"
  if [[ ! -e "$path" ]]; then
    echo "Not found: $path" >&2
    exit 1
  fi
  path="$(cd "$path" && pwd)"
  if [[ -f "${path}/META.txt" ]]; then
    printf '%s\n' "$path"
    return 0
  fi
  if [[ -L "${path}/latest" ]]; then
    local target=""
    if target="$(readlink -f "${path}/latest" 2>/dev/null)"; then
      :
    else
      target="$(readlink "${path}/latest")"
      [[ "$target" == /* ]] || target="${path}/${target}"
    fi
    if [[ -f "${target}/META.txt" ]]; then
      printf '%s\n' "$(cd "$target" && pwd)"
      return 0
    fi
  fi
  # newest snapshots/*
  local newest
  newest="$(ls -1dt "${path}"/snapshots/* 2>/dev/null | head -1 || true)"
  if [[ -n "$newest" && -f "${newest}/META.txt" ]]; then
    printf '%s\n' "$(cd "$newest" && pwd)"
    return 0
  fi
  echo "No usable snapshot under: $path" >&2
  echo "Expected META.txt in a snapshot dir, or a backup root with latest/ / snapshots/." >&2
  exit 1
}

prepare_snapshot_dirs() {
  local dest="$1"
  mkdir -p "${dest}/snapshots"
  SNAP_NAME="$(stamp_now)"
  SNAP_DIR="${dest}/snapshots/${SNAP_NAME}"
  mkdir -p "${SNAP_DIR}"
  PREV_LINK=""
  if [[ -L "${dest}/latest" ]]; then
    PREV_LINK="$(readlink "${dest}/latest")"
    if [[ "${PREV_LINK}" != /* ]]; then
      PREV_LINK="${dest}/${PREV_LINK}"
    fi
  fi
}

finalize_snapshot() {
  local dest="$1"
  ln -sfn "snapshots/${SNAP_NAME}" "${dest}/latest"
  echo "Snapshot ready: ${SNAP_DIR}"
  echo "Latest pointer: ${dest}/latest -> snapshots/${SNAP_NAME}"
}

prune_snapshots() {
  local dest="$1"
  local keep="$2"
  [[ -n "$keep" ]] || return 0
  keep="$(printf '%s' "$keep" | tr -dc '0-9')"
  [[ -n "$keep" && "$keep" -ge 1 ]] || return 0
  mapfile -t snaps < <(ls -1dt "${dest}"/snapshots/* 2>/dev/null || true)
  local total="${#snaps[@]}"
  if (( total <= keep )); then
    echo "Retention: keeping all ${total} snapshot(s) (limit ${keep})."
    return 0
  fi
  local i
  for (( i = keep; i < total; i++ )); do
    echo "Pruning old snapshot: ${snaps[$i]}"
    rm -rf "${snaps[$i]}"
  done
}

rsync_incremental() {
  # rsync_incremental SRC_DIR DEST_FILES_DIR PREV_FILES_DIR_OR_EMPTY
  local src="$1"
  local dst="$2"
  local prev="${3:-}"
  mkdir -p "$dst"
  local -a args=(-aH --delete --info=stats2)
  if [[ -n "$prev" && -d "$prev" ]]; then
    args+=(--link-dest="$prev")
    echo "    Incremental vs: $prev"
  else
    echo "    Full copy (first snapshot or no previous files/)."
  fi
  rsync "${args[@]}" "${src}/" "${dst}/"
}

write_meta() {
  local snap="$1"
  local stack="$2"
  local note="$3"
  cat >"${snap}/META.txt" <<EOF
stack=${stack}
created=$(date -Iseconds)
host=$(hostname 2>/dev/null || echo unknown)
note=${note}
EOF
}



wait_nextcloud_ready() {
  echo "Waiting for Nextcloud to become ready..."
  local i
  for i in $(seq 1 90); do
    if occ status 2>/dev/null | grep -q 'installed: true'; then
      echo "Nextcloud is installed and reachable via occ."
      return 0
    fi
    sleep 2
  done
  echo "Nextcloud did not report installed:true in time." >&2
  compose logs --tail=80 nextcloud >&2 || true
  exit 1
}

post_restore_nextcloud() {
  echo "==> Bringing Nextcloud out of maintenance / repairing DB metadata..."
  occ maintenance:mode --off || true
  occ db:add-missing-indices || true
  occ db:add-missing-columns || true
  occ db:add-missing-primary-keys || true
  occ maintenance:repair --include-expensive || true
  echo "==> Re-scanning files (this can take a long time on large libraries)..."
  occ files:scan --all
  occ files:scan-app-data || true
  if [[ -x "${ROOT}/configure-office.sh" ]]; then
    echo "==> Re-applying Collabora / trusted domain settings for this host..."
    "${ROOT}/configure-office.sh" || echo "Warning: configure-office.sh had errors — check Office manually." >&2
  fi
  echo "==> Optional verify: ./verify-office.sh"
}

do_backup() {
  need_rsync
  need docker
  docker compose version >/dev/null
  [[ -n "$DEST" ]] || { echo "Provide --dest /path" >&2; exit 1; }
  [[ -f .env ]] || { echo "No .env — run ./install.sh first." >&2; exit 1; }
  DEST="$(mkdir -p "$DEST" && cd "$DEST" && pwd)"
  load_env
  prepare_snapshot_dirs "$DEST"
  echo "==> Snapshot ${SNAP_NAME} -> ${SNAP_DIR}"

  # Quiesce app writes; keep DB up for a consistent dump, then sync files.
  echo "==> Enabling maintenance mode..."
  if compose ps -q nextcloud 2>/dev/null | grep -q .; then
    occ maintenance:mode --on || true
  fi

  echo "==> Dumping MariaDB..."
  if compose ps -q db 2>/dev/null | grep -q .; then
    compose exec -T db mariadb-dump \
      -u"${MYSQL_USER:-nextcloud}" \
      -p"${MYSQL_PASSWORD}" \
      --single-transaction \
      --routines \
      "${MYSQL_DATABASE:-nextcloud}" \
      >"${SNAP_DIR}/nextcloud-db.sql"
  else
    echo "Warning: db container not running — skipping SQL dump." >&2
  fi

  echo "==> Syncing Nextcloud files (data/html)..."
  local prev_files=""
  [[ -n "${PREV_LINK}" && -d "${PREV_LINK}/files" ]] && prev_files="${PREV_LINK}/files"
  if [[ -d data/html ]]; then
    rsync_incremental "data/html" "${SNAP_DIR}/files" "${prev_files}"
  else
    mkdir -p "${SNAP_DIR}/files"
  fi

  [[ -f .env ]] && cp -a .env "${SNAP_DIR}/"
  [[ -f docker-compose.yml ]] && cp -a docker-compose.yml "${SNAP_DIR}/"
  [[ -f docker-compose.redis.yml ]] && cp -a docker-compose.redis.yml "${SNAP_DIR}/"
  write_meta "${SNAP_DIR}" "$STACK_ID" "nextcloud html + mariadb dump"

  echo "==> Disabling maintenance mode..."
  if compose ps -q nextcloud 2>/dev/null | grep -q .; then
    occ maintenance:mode --off || true
  fi

  finalize_snapshot "$DEST"
  prune_snapshots "$DEST" "${KEEP}"
  echo
  echo "Tip: keep this backup root on an external drive or NAS (hardlinks need one filesystem)."
}

do_restore() {
  need docker
  docker compose version >/dev/null
  need_rsync
  [[ -n "$FROM" ]] || { echo "Provide --from /path" >&2; exit 1; }
  local snap
  snap="$(resolve_snapshot_dir "$FROM")"
  echo "Restoring from: $snap"
  grep -q "stack=${STACK_ID}" "${snap}/META.txt" 2>/dev/null || \
    echo "Warning: META stack id may not match ${STACK_ID} — continuing." >&2
  [[ -d "${snap}/files" ]] || { echo "Missing files/ in snapshot" >&2; exit 1; }

  echo
  cat <<'EOF'
This will REPLACE Nextcloud files and database with the snapshot so a new
host matches the old environment (then re-scan / repair automatically).

Recommended on a brand-new machine:
  1) ./install.sh   # pull images / create empty dirs once
  2) ./backup.sh --restore --from /path/to/backups
EOF
  read -r -p "Type 'restore' to continue: " confirm || true
  [[ "${confirm}" == "restore" ]] || { echo "Aborted."; exit 1; }

  echo "==> Stopping stack..."
  compose down 2>/dev/null || docker compose down 2>/dev/null || true

  echo "==> Restoring .env and files..."
  [[ -f "${snap}/.env" ]] && cp -a "${snap}/.env" .env
  load_env
  mkdir -p data/html data/db
  rm -rf data/html
  mkdir -p data/html
  rsync -aH "${snap}/files/" data/html/

  if [[ -f "${snap}/nextcloud-db.sql" ]]; then
    echo "==> Starting MariaDB and importing SQL..."
    # Fresh DB volume: remove old datadir so passwords in restored .env match
    if [[ -d data/db ]] && [[ -n "$(ls -A data/db 2>/dev/null || true)" ]]; then
      echo "    Replacing existing data/db so it matches restored .env passwords..."
      rm -rf data/db
      mkdir -p data/db
    fi
    compose up -d db
    wait_for_db
    # Wait for empty DB user grants after first init
    sleep 3
    compose exec -T db mariadb \
      -u"${MYSQL_USER:-nextcloud}" \
      -p"${MYSQL_PASSWORD}" \
      "${MYSQL_DATABASE:-nextcloud}" \
      <"${snap}/nextcloud-db.sql" \
      || compose exec -T db mariadb \
           -uroot \
           -p"${MYSQL_ROOT_PASSWORD}" \
           "${MYSQL_DATABASE:-nextcloud}" \
           <"${snap}/nextcloud-db.sql"
  else
    echo "Warning: no nextcloud-db.sql in snapshot — files only." >&2
  fi

  echo "==> Starting full stack..."
  compose up -d
  wait_for_db
  wait_for_redis
  wait_nextcloud_ready
  post_restore_nextcloud
  compose ps
  echo
  echo "Restore finished from ${snap}."
  echo "Open Nextcloud and confirm files/users look correct."
}

case "${MODE}" in
  backup) do_backup ;;
  restore) do_restore ;;
  *) usage >&2; exit 1 ;;
esac
