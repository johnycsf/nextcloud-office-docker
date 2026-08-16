# Breaking changes (read before updating)

**`git pull` by itself does not delete `data/` or restart containers.**  
A running Nextcloud keeps its current image and database until you `docker compose up` / re-run `install.sh`.

If you installed from an **older revision**, following the Update section is **not** a lossless in-place migration. **Back up `data/` first.**

## What changed

| Older clone | Current repo | Risk if you re-apply |
|-------------|--------------|----------------------|
| LinuxServer Nextcloud (`lscr.io/...`, `/config` bind) | Official `nextcloud` + `/var/www/html` | App will not understand old volume layout |
| Official Nextcloud on **SQLite** | Official Nextcloud + **MariaDB** (`MYSQL_*`) | Existing `config.php` stays SQLite; new MariaDB starts empty — mixed/unsupported. No automatic DB migration |
| No `db` service | `mariadb:lts` required | Compose file changes; passwords must exist in `.env` |

Nextcloud does **not** auto-convert SQLite → MariaDB. Treat MariaDB as a **new install** (or follow Nextcloud’s own DB conversion docs at your own risk).

## If you already have a working Nextcloud

1. **Do nothing** after `git pull` — keep serving the old compose revision.
2. Or pin the last working commit.
3. Or migrate deliberately: backup `data/`, move it aside, run a fresh `./manage.sh`, restore files into the new instance if needed.

`install.sh` refuses when it detects LinuxServer or SQLite data, unless:

```bash
I_UNDERSTAND_THIS_IS_A_FRESH_INSTALL=yes ./manage.sh install
```
