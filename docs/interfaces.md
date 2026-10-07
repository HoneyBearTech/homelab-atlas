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
| `APPDATA_ROOT` | yes | `/srv/appdata` | Host directory for files beside the config volumes: Radarr's custom scripts in `radarr/scripts` and `radarr4k/scripts`, mounted at `/scripts`. |
| `CONFIG_VOLUME_PREFIX` | yes | `homelab-atlas_` | Prefix of the Docker volumes with each app's config and database: `<prefix>radarr`, `<prefix>radarr4k`, `<prefix>sonarr`, `<prefix>sonarr4k`, `<prefix>lidarr`, `<prefix>bazarr`, `<prefix>bazarr4k`, `<prefix>sabnzbd`. |
| `RECYCLARR_CONFIG_PATH` | yes | `/srv/appdata/recyclarr` | Host directory with Recyclarr's config, mounted at `/config`. |

## Services and ports

| Service | Image | Host port → container | Web UI |
| --- | --- | --- | --- |
| `radarr` | `lscr.io/linuxserver/radarr` | 7878 → 7878 | yes |
| `radarr4k` | `lscr.io/linuxserver/radarr` | 17878 → 7878 | yes |
| `sonarr` | `lscr.io/linuxserver/sonarr` | 8989 → 8989 | yes |
| `sonarr4k` | `lscr.io/linuxserver/sonarr` | 8888 → 8989 | yes |
| `lidarr` | `lscr.io/linuxserver/lidarr` | 8686 → 8686 | yes |
| `bazarr` | `lscr.io/linuxserver/bazarr` | 6767 → 6767 | yes |
| `bazarr4k` | `lscr.io/linuxserver/bazarr` | 6768 → 6767 | yes |
| `sabnzbd` | `lscr.io/linuxserver/sabnzbd` | 8080 → 8080 | yes |
| `flaresolverr` | `ghcr.io/flaresolverr/flaresolverr` | 8191 → 8191 | no (API for the apps) |
| `recyclarr` | `recyclarr/recyclarr` | none | no (runs daily) |
| `dozzle` | `amir20/dozzle` | 4040 → 8080 | yes (container logs) |

Ports are published on every host interface. Exact versions and digests are in [`compose.yaml`](../compose.yaml).

## Volumes and mounts

| Container path | Host source | Services |
| --- | --- | --- |
| `/config` | volume `<CONFIG_VOLUME_PREFIX><app>` | the *arr apps, Bazarr, SABnzbd |
| `/config` | `RECYCLARR_CONFIG_PATH` | recyclarr |
| `/media` | `MEDIA_ROOT` | the *arr apps, Bazarr, SABnzbd |
| `/scripts` | `APPDATA_ROOT/radarr/scripts`, `APPDATA_ROOT/radarr4k/scripts` | radarr, radarr4k |
| `/var/run/docker.sock` (read-only) | the Docker socket | dozzle (an allowed exception, see below) |

FlareSolverr keeps nothing worth backing up; Docker gives it an anonymous volume.

## Labels

| Label | Meaning |
| --- | --- |
| `org.honeybeartech.atlas.allow.<rule>` | Lets one service break one policy rule; the value is the reason, and must not be empty. Rules: `image`, `digest`, `latest`, `build`, `privileged`, `cap-add`, `host-network`, `host-pid`, `docker-socket` ([security.md](security.md#policy)). In use: `dozzle` (`docker-socket`). |

## Commands

| Command | Does |
| --- | --- |
| `docker compose up -d` / `down` / `ps` / `logs <service>` | Runs and inspects the stack |
| `make check` | `docker compose config --format json \| python scripts/check_compose.py`: the policy check |
| `python scripts/check_compose.py [FILE] [--sbom OUT]` | Checks a resolved Compose config (from `FILE` or stdin); `--sbom` also writes a CycloneDX 1.6 SBOM of the images. Exit 0 = no violations, 1 = violations (one line each), 2 = unreadable input |
| `make test`, `make lint` | The checker's tests and the linters |

## Outbound connections

From the host: the image registries (`lscr.io`, `ghcr.io`, Docker Hub) on `docker compose pull`. From the apps:
the indexers, the Usenet provider and metadata services they're configured for; Recyclarr fetches the TRaSH
Guides from GitHub and calls the Radarr and Sonarr APIs.

## Release files

Each GitHub Release has `homelab-atlas-<version>.tar.gz` (source, with `LICENSE`),
`homelab-atlas-<version>.cdx.json` (CycloneDX SBOM of the pinned images), `SHA256SUMS` and its Sigstore
bundle, and SLSA provenance ([verifying-releases.md](verifying-releases.md)).
