# nextcloud-office-docker

![Repobeats analytics image](https://repobeats.axiom.co/api/embed/555276754948a1ca10af5154e021e18f1b4d4011.svg "Repobeats analytics image")


[![Sponsor](https://img.shields.io/badge/Sponsor-%E2%9D%A4-ea4aaa?logo=githubsponsors&logoColor=white)](https://github.com/sponsors/johnycsf)

Deploy [Nextcloud](https://nextcloud.com/) with Docker Compose, including **LibreOffice document editing** via [Collabora Online](https://www.collaboraonline.com/code/).

Uses the **official** [`nextcloud`](https://hub.docker.com/_/nextcloud) image, Collabora’s official [`collabora/code`](https://hub.docker.com/r/collabora/code) image, and **official** [`mariadb:lts`](https://hub.docker.com/_/mariadb) (not SQLite).

> **Updating an older clone?** `git pull` alone will not delete `data/`. Re-running `./install.sh` / Compose against LinuxServer or SQLite data is **not** supported in-place. Read [BREAKING-CHANGES.md](BREAKING-CHANGES.md).

Kubernetes version: [nextcloud-office-k8s](https://github.com/johnycsf/nextcloud-office-k8s)

## Why MariaDB

Nextcloud’s docs treat SQLite as testing/minimal only. [MariaDB and PostgreSQL are recommended](https://docs.nextcloud.com/server/latest/admin_manual/configuration_database/linux_database_configuration.html). This repo follows the [official Nextcloud Docker Compose MariaDB example](https://github.com/nextcloud/docker#running-this-image-with-docker-compose):

- Image: `mariadb:lts`
- `transaction-isolation=READ-COMMITTED` (required)
- `binlog-format=ROW` + `utf8mb4` / `utf8mb4_bin` (admin manual guidance)
- Nextcloud auto-config via `MYSQL_HOST` / `MYSQL_DATABASE` / `MYSQL_USER` / `MYSQL_PASSWORD`

## Why Office needs Collabora

**+ New → Document / Spreadsheet / Presentation** often appears in Nextcloud but does nothing useful until a separate Collabora Online server is connected. This repo follows [Nextcloud’s recommended approach](https://docs.nextcloud.com/server/latest/admin_manual/office/example-docker.html).


## Why this repo (not just another compose file)

- **`./manage.sh`** control center — install, update, backup, status/doctor, uninstall
- Interactive colored install with step progress
- Auto-detects your OS and installs missing host tools
- Safe **`./update.sh`** with automatic pre-update backup
- Incremental hardlink **`./backup.sh`** + restore
- **Official upstream images only**

## What you need

- A Linux host (Debian/Ubuntu, Fedora/RHEL, Arch, openSUSE, Alpine) or macOS with Homebrew
- `sudo` so `./install.sh` can install missing tools (Docker, curl, openssl, rsync, …)
- Enough disk for your data

`./install.sh` is interactive (colors + step progress), detects your OS, and installs host dependencies automatically.

## Install

```bash
git clone https://github.com/johnycsf/nextcloud-office-docker.git
cd nextcloud-office-docker
chmod +x manage.sh install.sh configure-office.sh verify-office.sh
./manage.sh          # interactive control center
# or: ./install.sh
# optional Redis: ./install.sh --include-redis
```

The script will:

1. Generate MariaDB passwords into `.env` (if still placeholders)
2. Start MariaDB + Nextcloud + Collabora (and Redis if you passed `--include-redis`)
3. Wait for you to create the Nextcloud admin account (DB is already wired)
4. Wire Nextcloud Office to Collabora
5. Run connectivity + database checks

Then try: **+ New → Document**.

### Optional Redis

Redis is **not** required. It helps with caching and file locking under more concurrent use, matching the [official Nextcloud Compose example](https://github.com/nextcloud/docker#running-this-image-with-docker-compose).

```bash
./install.sh --include-redis
```

That sets `ENABLE_REDIS=yes` in `.env` and applies `docker-compose.redis.yml` (`redis:alpine` + `REDIS_HOST=redis`). Re-running `./install.sh` later keeps Redis if already enabled.

Fresh data only — do **not** reuse an old SQLite `data/html` tree with this MariaDB setup.

### Verify anytime

```bash
./verify-office.sh
```

Checks include Collabora wiring and `dbtype=mysql` (MariaDB).

### If Office fails — set your real LAN address

`NEXTCLOUD_HOST` / `COLLABORA_HOST` are the address **your browser uses** to reach this machine (your home LAN IP or hostname).  
`192.168.1.50` is only an **example** — replace it with yours.

```bash
# Example only — use YOUR LAN IP or hostname
NEXTCLOUD_HOST=192.168.0.20 COLLABORA_HOST=192.168.0.20 ./configure-office.sh
```

## Customize

Edit `.env` (from `.env.example`): timezone, ports, hostnames, MariaDB credentials.

| Path | Purpose |
|------|---------|
| `./data/html` | Nextcloud files (`/var/www/html`) |
| `./data/db` | MariaDB data (`/var/lib/mysql`) |

## Update

Keep the stack current (safe while running; brief recreate downtime):

```bash
chmod +x update.sh
./update.sh
```

Before changing anything, the script runs `./backup.sh` into `./backups` (incremental, database-safe). After a successful update it asks whether to **keep** or **delete** that snapshot, and how many local copies to retain (older ones are pruned). Copy important backups to an external drive, NAS, or cloud so they do not fill this disk.

To roll back later (same tool as disaster recovery):

```bash
./backup.sh --restore --from ./backups
# or from an external copy:
./backup.sh --restore --from /mnt/usb/my-backups
```

Older `backups/update-*` tarball folders (from previous script versions) are no longer used by `./update.sh`; use each folder's `RESTORE.txt` if you still need one, or delete them to free space.

This pulls/rebuilds images, recreates containers as needed, and runs `docker image prune` for **dangling** (untagged) images only — it will not wipe other projects' images or your `data/` volume.

Afterward you can run `./verify-office.sh`. Re-run `./configure-office.sh` only if your LAN IP/hostname changed.

Upgrade Nextcloud **one major version at a time**.

SQLite / LinuxServer installs: see [BREAKING-CHANGES.md](BREAKING-CHANGES.md).


## Disaster recovery (full backup / restore)

Incremental snapshots via `rsync` hardlinks (unchanged files are not re-copied). `./update.sh` uses this same `backup.sh` before updating (into `./backups`).

```bash
chmod +x backup.sh

# Backup to USB/NAS/external path (repeat anytime; later runs are incremental)
./backup.sh --dest /mnt/usb/nextcloud-office-docker-backups
./backup.sh --dest /mnt/usb/nextcloud-office-docker-backups --keep 5   # optional: retain only newest N

# On a brand-new machine/cluster after ./install.sh:
./backup.sh --restore --from /mnt/usb/nextcloud-office-docker-backups
# or a specific snapshot:
./backup.sh --restore --from /mnt/usb/nextcloud-office-docker-backups/snapshots/YYYYMMDD-HHMMSS
```

Each snapshot includes `SHA256SUMS` plus a `snapshot_sha256` key in `META.txt`. Restore verifies these and **warns** (does not abort) if integrity is lost.

Keep the backup root on **one filesystem** so hardlinks work. Prefer an external drive, NAS, or cloud sync of that folder.

**Database safety:** Nextcloud uses a verified MariaDB *logical* dump (`mariadb-dump --single-transaction`) — the live `data/db` / DB PVC files are never rsync'd. SQLite apps (Heimdall, Vaultwarden) are stopped or scaled to 0, WAL-checkpointed when `sqlite3` is available, integrity-checked, then copied. Incremental hardlinks apply to file trees; each SQL dump is a full verified file with a SHA-256 in `META.txt`.


For Nextcloud, restore also imports MariaDB, runs `occ` repair helpers, and `files:scan --all` with a live **percentage progress bar** (can still take a long time on large libraries), then re-applies Office/trusted-domain settings when possible.

## Uninstall

```bash
docker compose down
rm -rf data .env
```

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| New → Document blank/spins | Open `http://YOUR_IP:9980/hosting/discovery` from your PC |
| Wrong IP after DHCP change | Re-run `./configure-office.sh` with the new host |
| Collabora OOM | Free RAM or raise Docker memory limits |
| `dbtype` is `sqlite` | Remove `data/` and re-run `./install.sh` so `MYSQL_*` auto-config applies on first install |


## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## Support this work

If these homelab tools save you time, please consider sponsoring:

[![Sponsor johnycsf](https://img.shields.io/badge/GitHub%20Sponsors-Donate-ea4aaa?logo=githubsponsors&logoColor=white)](https://github.com/sponsors/johnycsf)

👉 **[github.com/sponsors/johnycsf](https://github.com/sponsors/johnycsf)** — tips and monthly support keep these beginner-friendly stacks maintained.

