# nextcloud-office-docker

Deploy [Nextcloud](https://nextcloud.com/) with Docker Compose, including **LibreOffice document editing** via [Collabora Online](https://www.collaboraonline.com/code/).

Kubernetes version: [nextcloud-office-k8s](https://github.com/johnycsf/nextcloud-office-k8s)

## Why Office needs Collabora

**+ New → Document / Spreadsheet / Presentation** often appears in Nextcloud but does nothing useful until a separate Collabora Online server is connected. This repo follows [Nextcloud’s recommended approach](https://docs.nextcloud.com/server/latest/admin_manual/office/example-docker.html).

## What you need

- Docker with Compose plugin
- About **3 GiB RAM** free for Collabora in addition to Nextcloud
- A browser that can reach this machine on ports **443** (Nextcloud) and **9980** (Collabora)

## Install

```bash
git clone https://github.com/johnycsf/nextcloud-office-docker.git
cd nextcloud-office-docker
chmod +x install.sh configure-office.sh verify-office.sh
./install.sh
```

The script will:

1. Start Nextcloud + Collabora
2. Wait for you to create the Nextcloud admin account
3. Wire Nextcloud Office to Collabora
4. Run connectivity checks

Then try: **+ New → Document**.

### Verify anytime

```bash
./verify-office.sh
```

If your IP/DNS changes:

```bash
NEXTCLOUD_HOST=192.168.1.50 COLLABORA_HOST=192.168.1.50 ./configure-office.sh
```

## Customize

Edit `.env` (from `.env.example`): timezone, `PUID`/`PGID`, ports, and hostnames.

Data lives in `./data/` (gitignored).

## Update

```bash
docker compose pull
docker compose up -d
./configure-office.sh
./verify-office.sh
```

Upgrade Nextcloud **one major version at a time**.

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

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).
