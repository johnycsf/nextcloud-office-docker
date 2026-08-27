# nextcloud-office-docker

[![Sponsor](https://img.shields.io/badge/Sponsor-%E2%9D%A4-ea4aaa?logo=githubsponsors&logoColor=white)](https://github.com/sponsors/johnycsf)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Issues](https://img.shields.io/badge/issues-welcome-lightgrey.svg)](../../issues/new/choose)

Nextcloud + Collabora Office — official images, guided install.

![`./manage.sh` control center](docs/manage-demo.gif)

## Install

```bash
git clone https://github.com/johnycsf/nextcloud-office-docker.git
cd nextcloud-office-docker
chmod +x manage.sh
./manage.sh
```

`./manage.sh` opens a **↑/↓ menu** with a `>` cursor (j/k and Enter also work). Install asks about optional Redis; `--include-redis` skips the question and enables it. Then create the Nextcloud admin account and try **+ New → Document**.

Uses the **official** [`nextcloud`](https://hub.docker.com/_/nextcloud) image, Collabora’s official [`collabora/code`](https://hub.docker.com/r/collabora/code) image, and **official** [`mariadb:latest`](https://hub.docker.com/_/mariadb) (not SQLite).

Kubernetes version: [nextcloud-office-k8s](https://github.com/johnycsf/nextcloud-office-k8s)

> **Updating an older clone?** `git pull` alone will not delete `data/`. Re-running `./manage.sh` / Compose against LinuxServer or SQLite data is **not** supported in-place. Read [BREAKING-CHANGES.md](BREAKING-CHANGES.md).

## Why Office needs Collabora

**+ New → Document / Spreadsheet / Presentation** often appears in Nextcloud but does nothing useful until a separate Collabora Online server is connected. This repo follows [Nextcloud’s recommended approach](https://docs.nextcloud.com/server/latest/admin_manual/office/example-docker.html) so Office is wired in the same stack.

## Why this repo (not just another compose file)

- **`./manage.sh`** control center — install, update, backup, status/doctor, uninstall
- Interactive colored install with step progress
- Auto-detects your OS and installs missing host tools
- Safe **`./manage.sh update`** with automatic pre-update backup
- Incremental hardlink **`./manage.sh backup`** + restore
- **Official upstream images only**

## What you need

- A Linux host (Debian/Ubuntu, Fedora/RHEL, Arch, openSUSE, Alpine) or macOS with Homebrew
- `sudo` so `./manage.sh` can install missing tools (Docker, curl, openssl, rsync, …)
- Enough disk for your data

## Customize

Edit `.env` (from `.env.example`): timezone, ports, hostnames, MariaDB credentials.

| Path | Purpose |
|------|---------|
| `./data/html` | Nextcloud files (`/var/www/html`) |
| `./data/db` | MariaDB data (`/var/lib/mysql`) |

Redis is **not** required. It helps with caching and file locking under more concurrent use, matching the [official Nextcloud Compose example](https://github.com/nextcloud/docker#running-this-image-with-docker-compose). Fresh data only — do **not** reuse an old SQLite `data/html` tree with this MariaDB setup.

### Verify anytime

```bash
./scripts/verify-office.sh
```

Checks include Collabora wiring and `dbtype=mysql` (MariaDB).

### If Office fails — set your real LAN address

`NEXTCLOUD_HOST` / `COLLABORA_HOST` are the address **your browser uses** to reach this machine (your home LAN IP or hostname). `192.168.1.50` is only an **example**.

```bash
# Example only — use YOUR LAN IP or hostname
NEXTCLOUD_HOST=192.168.0.20 COLLABORA_HOST=192.168.0.20 ./scripts/configure-office.sh
```

## Update

```bash
./manage.sh update
```

Before changing anything, the script runs `./manage.sh backup` into `./backups` (incremental, database-safe). After a successful update it asks whether to **keep** or **delete** that snapshot, and how many local copies to retain. Copy important backups to an external drive, NAS, or cloud so they do not fill this disk.

This pulls/rebuilds images, recreates containers as needed, and runs `docker image prune` for **dangling** (untagged) images only — it will not wipe other projects' images or your `data/` volume.

Afterward you can run `./scripts/verify-office.sh`. Re-run `./scripts/configure-office.sh` only if your LAN IP/hostname changed. Upgrade Nextcloud **one major version at a time**. SQLite / LinuxServer installs: see [BREAKING-CHANGES.md](BREAKING-CHANGES.md).

## Backup and restore

Incremental snapshots via `rsync` hardlinks (unchanged files are not re-copied). Prefer an external drive, NAS, or cloud sync of that folder — hardlinks need **one filesystem**.

```bash
./manage.sh backup --dest /mnt/usb/nextcloud-office-docker-backups
./manage.sh backup --dest /mnt/usb/nextcloud-office-docker-backups --keep 5
```

Restore (this machine or a new one after `./manage.sh`):

```bash
./manage.sh backup --restore --from /mnt/usb/nextcloud-office-docker-backups
# or a local snapshot tree / specific snapshot:
./manage.sh backup --restore --from ./backups
./manage.sh backup --restore --from /mnt/usb/nextcloud-office-docker-backups/snapshots/YYYYMMDD-HHMMSS
```

Each snapshot includes `SHA256SUMS` plus a `snapshot_sha256` key in `META.txt`. Restore verifies these and **warns** (does not abort) if integrity is lost.

**Database safety:** Nextcloud uses a verified MariaDB *logical* dump (`mariadb-dump --single-transaction`) — the live `data/db` files are never rsync'd. Incremental hardlinks apply to file trees; each SQL dump is a full verified file with a SHA-256 in `META.txt`. Restore also imports MariaDB, runs `occ` repair helpers, and `files:scan --all`, then re-applies Office/trusted-domain settings when possible.

Older `backups/update-*` tarball folders (from previous script versions) are no longer used by `./manage.sh update`; use each folder's `RESTORE.txt` if you still need one.

## Uninstall

```bash
docker compose down
rm -rf data .env
```

Or use **Uninstall** in `./manage.sh`.

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| New → Document blank/spins | Open `http://YOUR_IP:9980/hosting/discovery` from your PC |
| Wrong IP after DHCP change | Re-run `./scripts/configure-office.sh` with the new host |
| Collabora OOM | Free RAM or raise Docker memory limits |
| `dbtype` is `sqlite` | Remove `data/` and re-run `./manage.sh` so `MYSQL_*` auto-config applies on first install |

## Host ports

During `./manage.sh` (or Manage → Install / reconfigure), the script checks whether default host ports are free, lets you keep the defaults or choose different ports, and saves them in `.env`. Re-running install keeps your current ports unless you change them.

Non-interactive: set the port variables in `.env` (or the environment) and use `SKIP_PORT_PROMPTS=1`.

Defaults are kept unique across the johnycsf stacks so you can run several on one host without a clash:

| Stack | Variable | Default host port |
|-------|----------|-------------------|
| `heimdall-docker` | `HTTP_PORT` | `8080` |
| `vaultwarden-docker` | `PORT` | `8081` |
| `nextcloud-office-docker` | `NEXTCLOUD_PORT` | `8082` |
| `nextcloud-office-docker` | `COLLABORA_PORT` | `9980` |
| `immich-docker` | `IMMICH_PORT` | `2283` |

Install also refuses a port another stack checked out beside this one already claims in its `.env` — even when that stack is stopped — and offers the next free port instead.

All defaults are `>= 1024` because **rootless Podman cannot publish privileged ports** (`80`, `443`). On Docker you may still set `HTTP_PORT=80` if you want.

## Container engine

During `./manage.sh` → Install you can choose **Docker** or **Podman**. The choice is saved as `CONTAINER_ENGINE` in `.env`. All manage actions (`update`, `backup`, `restore`, …) use that engine via a shared `compose` helper.

## Backup exports

> **Note:** After containers start, some files under `data/` may be root-owned. Install/restore automatically fixes ownership for the invoking user so host-side `rsync` backup/restore does not fail with permission errors.

Local snapshots stay as incremental hardlink trees (fast rollback). Optionally create a compressed offsite copy with `./manage.sh backup --dest ./backups --archive tar.gz|tar.xz|zip` (add `--archive-password` for zip password or age-passphrase on tar). For stronger key-based encryption use `--encrypt` (age). See repo-framework `docs/BACKUP_ENCRYPTION.md`.

## Credits

This repo packages or configures upstream software. See [CREDITS.md](CREDITS.md) for the main developers and projects this work builds on.

## Disclaimer

This project is provided **as is**. The author is **not responsible** for any loss, damage, data corruption, downtime, security issues, or other consequences from using it. Full text: [DISCLAIMER.md](DISCLAIMER.md).

## Bug reports & contributions

If you hit an error, please [open a GitHub Issue](../../issues/new/choose) and follow [CONTRIBUTING.md](CONTRIBUTING.md). Fixes via Pull Request are welcome. GitHub Issues/PRs are the supported way to report problems—there is no private support channel.

## Security

See [SECURITY.md](SECURITY.md) for how to report vulnerabilities.

## Image registry configuration

This repository defaults to pulling images from docker.io. To override the registry for deployments or compose, set the `IMAGE_REGISTRY` environment variable or add it to `.env` (default: `docker.io`). Examples:

- Compose: set `IMAGE_REGISTRY` in `.env` or export it before running compose.
- Kubernetes: use envsubst when applying manifests, e.g.:

  `IMAGE_REGISTRY=registry.example.com envsubst < deploy.yaml | kubectl apply -f -`

Sponsorship funds testing and maintenance: [github.com/sponsors/johnycsf](https://github.com/sponsors/johnycsf).
