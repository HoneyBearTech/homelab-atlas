# Interfaces

Everything homelab-atlas reads, exposes or runs. homelab-atlas has no HTTP API of its own; the apps' web UIs
and APIs are documented by their projects.

## Settings

### `.env`

Read by `docker compose` from `.env` next to `compose.yaml` (template: [`.env.example`](../.env.example)). A
setting marked required stops `docker compose` with an error naming it when it's missing.

| Setting | Required | Example | Meaning |
| --- | --- | --- | --- |
| `PUID`, `PGID` | yes | `1000` | User and group the apps run as and write files as. Must be able to read and write `MEDIA_ROOT` and `RECYCLARR_CONFIG_PATH`. |
| `TZ` | yes | `Etc/UTC` | Time zone (tz database name) for logs and schedules. |
| `UMASK` | no (default `002`) | `002` | File creation mask inside the linuxserver.io apps; `002` keeps files group-writable without making them world-writable. |
| `MEDIA_ROOT` | yes | `/srv/media` | Host directory with downloads and media on one filesystem, mounted at `/media` in Radarr, Sonarr, Lidarr, Bazarr and SABnzbd. |
| `APPDATA_ROOT` | yes | `/srv/appdata` | Host directory for files beside the config directories: Radarr's custom scripts in `radarr/scripts` and `radarr4k/scripts`, mounted at `/scripts`. |
| `CONFIG_ROOT` | yes | `/srv/config` | Host directory with each app's config directory (settings, API key and database), `<app>/config` for `radarr`, `radarr4k`, `sonarr`, `sonarr4k`, `lidarr`, `bazarr`, `bazarr4k` and `sabnzbd`, mounted at `/config`; owned by `PUID:PGID`. Holds every app's API key: back it up. |
| `SABNZBD_INCOMPLETE_PATH` | yes | `/srv/downloads/incomplete` | Host directory where SABnzbd assembles downloads before they're complete, mounted at `/incomplete` (its temporary download folder). May be another disk or share; not backed up. |
| `RECYCLARR_CONFIG_PATH` | yes | `/srv/appdata/recyclarr` | Host directory with Recyclarr's config, mounted at `/config`. |

### `autoheal.env`

Read by the `autoheal` service (template: [`autoheal.env.example`](../autoheal.env.example)); optional, mode
`600`, gitignored.

| Setting | Meaning |
| --- | --- |
| `WEBHOOK_URL` | Where autoheal posts a notice each time it restarts a container (a secret). A Discord channel webhook works as is; empty or missing = log only |

### `backup.env`

Read by `scripts/scheduled-backup.sh` (template: [`backup.env.example`](../backup.env.example)); optional, mode
`600`, gitignored. Read as data (`KEY=value` lines), never sourced; an unknown key is an error. `BACKUP_ENV_FILE`
names another file.

| Setting | Meaning |
| --- | --- |
| `BACKUP_DIR` | Where backups are written (default `backups` in the checkout) |
| `BACKUP_KEEP` | How many backups are kept in `BACKUP_DIR`, the newest (default `3`) |
| `BACKUP_REMOTE` | Where each backup is copied with rsync, such as `backup-host:/volume1/atlas-backups`; empty = no copy off the host |
| `BACKUP_REMOTE_KEEP` | How many backups are kept at `BACKUP_REMOTE`, the newest (default `30`) |
| `BACKUP_PING_URL` | An Uptime Kuma push URL (a secret), told `up` after a good run and `down` after a failed one; empty = no reports |

## Services and ports

| Service | Image | Host port → container | Web UI |
| --- | --- | --- | --- |
| `radarr` | `lscr.io/linuxserver/radarr` | 7878 → 7878 | yes |
| `radarr4k` | `lscr.io/linuxserver/radarr` | 17878 → 7878 | yes |
| `sonarr` | `lscr.io/linuxserver/sonarr` | 8989 → 8989 | yes |
| `sonarr4k` | `lscr.io/linuxserver/sonarr` | 8988 → 8989 | yes |
| `lidarr` | `lscr.io/linuxserver/lidarr` | 8686 → 8686 | yes |
| `bazarr` | `lscr.io/linuxserver/bazarr` | 6767 → 6767 | yes |
| `bazarr4k` | `lscr.io/linuxserver/bazarr` | 6768 → 6767 | yes |
| `sabnzbd` | `lscr.io/linuxserver/sabnzbd` | 8080 → 8080 | yes |
| `recyclarr` | `recyclarr/recyclarr` | none | no (runs daily) |
| `dozzle` | `amir20/dozzle` | 7007 → 7007 | no (agent for the Dozzle hub on another host) |
| `autoheal` | `willfarrell/autoheal` | none | no (restarts unhealthy services) |
| `socket-proxy` | `lscr.io/linuxserver/socket-proxy` | none (internal network `docker-proxy`) | no |

Ports are published on every host interface. Exact versions and digests are in [`compose.yaml`](../compose.yaml).

## Volumes and mounts

| Container path | Host source | Services |
| --- | --- | --- |
| `/config` | `CONFIG_ROOT/<app>/config` | the *arr apps, Bazarr, SABnzbd |
| `/config` | `RECYCLARR_CONFIG_PATH` | recyclarr |
| `/media` | `MEDIA_ROOT` | the *arr apps, Bazarr, SABnzbd |
| `/scripts` | `APPDATA_ROOT/radarr/scripts`, `APPDATA_ROOT/radarr4k/scripts` | radarr, radarr4k |
| `/incomplete` | `SABNZBD_INCOMPLETE_PATH` | sabnzbd |
| `/var/run/docker.sock` (read-only) | the Docker socket | dozzle, socket-proxy (allowed exceptions, see below) |

`socket-proxy` and `autoheal` share the internal network `docker-proxy`, which has no route out and nothing
published; autoheal also joins the default network, to reach its webhook.

## Labels

| Label | Meaning |
| --- | --- |
| `org.honeybeartech.atlas.allow.<rule>` | Lets one service break one policy rule; the value is the reason, and must not be empty. Rules: `image`, `digest`, `latest`, `build`, `privileged`, `no-new-privileges`, `cap-drop`, `cap-add`, `host-network`, `host-pid`, `docker-socket`, `devices`, `healthcheck` ([security.md](security.md#policy)). In use: `dozzle` and `socket-proxy` (`docker-socket`), `autoheal` (`latest`). |
| `autoheal` | `"true"` on every service autoheal may restart when its health check fails (every app service and socket-proxy). |
| `org.honeybeartech.atlas.backup.skip` | Container paths (comma-separated, exact) that `scripts/backup.sh` never archives and `scripts/restore.sh` refuses to write, even if a backup lists them: data too large to back up here or disposable. In use: `/media` on every service that mounts it, and `/incomplete` on SABnzbd, so a backup holds only the apps' `/config`, Recyclarr's `/config` and Radarr's `/scripts`. |
| `org.honeybeartech.atlas.backup.exclude` | Paths inside a service's data mounts (comma-separated, exact container paths, at any depth) that `scripts/backup.sh` leaves out of the mount's archive and `scripts/restore.sh` leaves in place. A path that isn't inside one of the service's data mounts, or contains `..` or a pattern character (`*?[\`), makes both fail before anything stops. In use: `/config/MediaCover` (posters the app downloads again) on Radarr, Radarr 4K, Sonarr, Sonarr 4K and Lidarr. |

## Commands

| Command | Does |
| --- | --- |
| `docker compose up -d` / `down` / `ps` / `logs <service>` | Runs and inspects the stack |
| `make check` | `docker compose config --format json \| python scripts/check_compose.py`: the policy check |
| `python scripts/check_compose.py [FILE] [--sbom OUT]` | Checks a resolved Compose config (from `FILE` or stdin); `--sbom` also writes a CycloneDX 1.6 SBOM of the images. Exit 0 = no violations, 1 = violations (one line each), 2 = unreadable input |
| `make test`, `make lint` | The checker's tests and the linters |
| `scripts/backup.sh [DIR]` | Archives every service's data mounts (every read-write volume or bind mount except the Docker socket, anonymous volumes and the paths in the service's `backup.skip` label; a mount inside another mount is archived on its own and left out of the outer archive), `.env` and any `<service>.env` into `DIR` (default `backups/<date>-<time>`, gitignored) as `<service>--<path>.tar.gz` (such as `radarr--config.tar.gz`), with a `MANIFEST` (tab-separated: archive, service, container path, source, image), `NETWORKS` (the address range of each network the stack uses but doesn't create), `VERSION` (the checkout's `git describe`) and `SHA256SUMS`, all mode `600`. Each service is stopped only while its own mounts are copied and started again (with any service Compose stopped along with it) before the copies are compressed (with `pigz` when it's installed, else `gzip`). Leaves out the paths a service's `org.honeybeartech.atlas.backup.exclude` label lists. Exit 0 = backup complete |
| `scripts/restore.sh [--yes] DIR [SERVICE...]` | Verifies `DIR/SHA256SUMS`, checks the `MANIFEST`, creates missing containers, asks for confirmation (unless `--yes`), stops the services, recreates a service's container if it predates `compose.yaml`, replaces the contents of each listed mount with its archive (owners and modes kept), and starts what was running. Each archive goes to what the service mounts at that container path now, whatever the `MANIFEST` names as its source (so a backup of a Docker volume restores into a config directory), and a missing directory is created. Writes only mounts the service still has read-write; never the Docker socket, a path in the service's `backup.skip` label (`/media`, `/incomplete`), another mount inside the one it restores, or a path in its `backup.exclude` label. Reads only backups made by this version or later (older ones: the previous release's `restore.sh`) |
| `scripts/scheduled-backup.sh` | `scripts/backup.sh`, then a copy to `BACKUP_REMOTE` (`SHA256SUMS` last), pruning to the newest `BACKUP_KEEP` / `BACKUP_REMOTE_KEEP`, and a report to `BACKUP_PING_URL` ([`backup.env`](#backupenv)). Run nightly by `deploy/systemd/homelab-atlas-backup.timer` (03:00). Exit 0 = backed up and copied |
| `make smoke` | `scripts/smoke-test.sh`: starts every service under a separate Compose project with throwaway directories (owned by `PUID:PGID`, mode 0755, as on a host), volumes and networks (from `.env.example`), no fixed container names, no published ports and no env files; waits until all are healthy, round-trips a backup and restore over every data mount (checking that skipped mounts and excluded paths are neither archived nor overwritten, and that an app's config restores through a container made from older settings into a config directory that was removed), runs the scheduled backup against a stand-in backup server, makes a test container unhealthy and checks that autoheal restarts it, then removes what it created. Exit 0 = all passed |

## Outbound connections

From the host: the image registries (`lscr.io`, `ghcr.io`, Docker Hub) on `docker compose pull`. From the apps:
the indexers, the Usenet provider and metadata services they're configured for; Recyclarr fetches the TRaSH
Guides from GitHub and calls the Radarr and Sonarr APIs. The scheduled backup connects to `BACKUP_REMOTE` (rsync
over SSH) and `BACKUP_PING_URL` (HTTPS), when they're set.

## Release files

Each GitHub Release has `homelab-atlas-<version>.tar.gz` (source, with `LICENSE`),
`homelab-atlas-<version>.cdx.json` (CycloneDX SBOM of the pinned images), `SHA256SUMS` and its Sigstore
bundle, and SLSA provenance ([verifying-releases.md](verifying-releases.md)).
