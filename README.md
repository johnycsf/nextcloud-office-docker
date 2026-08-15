# nextcloud-office-docker

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

## What you need

- Docker with Compose plugin
- About **3 GiB RAM** free for Collabora in addition to Nextcloud + MariaDB
- A browser that can reach this machine on ports **80** (Nextcloud) and **9980** (Collabora)

## Install

```bash
git clone https://github.com/johnycsf/nextcloud-office-docker.git
cd nextcloud-office-docker
chmod +x install.sh configure-office.sh verify-office.sh
./install.sh
# optional Redis (official caching / file locking):
# ./install.sh --include-redis
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

Only for installs that **already** use official Nextcloud + MariaDB from this repo:

```bash
./install.sh          # or: ./install.sh --include-redis
./configure-office.sh
./verify-office.sh
```

Upgrade Nextcloud **one major version at a time**.

If you still run SQLite or LinuxServer volumes, do **not** use the Update steps after a pull — see [BREAKING-CHANGES.md](BREAKING-CHANGES.md).

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

## Repository activity

![Repobeats analytics image](https://repobeats.axiom.co/api/embed/555276754948a1ca10af5154e021e18f1b4d4011.svg "Repobeats analytics image")

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).
