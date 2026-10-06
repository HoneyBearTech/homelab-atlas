# Interfaces

Everything homelab-atlas reads, exposes or runs. homelab-atlas has no HTTP API of its own; the apps' web
UIs and APIs are documented by their projects.

## Settings (`.env`)

Read by `docker compose` from `.env` next to `compose.yaml` (template: [`.env.example`](../.env.example)).
**Planned**: the stack that reads them isn't in the repository yet.

| Setting | Example | Meaning |
| --- | --- | --- |
| `PUID`, `PGID` | `1000` | User and group the apps run as and write files as. Must own `APPDATA_ROOT` and `DATA_ROOT`. |
| `TZ` | `Etc/UTC` | Time zone (tz database name) for logs and schedules. |
| `UMASK` | `002` | File creation mask inside the apps; `002` keeps files group-writable. |
| `APPDATA_ROOT` | `/srv/appdata` | Host directory with one subdirectory per app, mounted at `/config`. Holds API keys and databases: back it up, keep it private. |
| `DATA_ROOT` | `/srv/data` | Host directory with downloads and media, mounted at `/data` in every app that moves files. |

## Ports

**Planned.** Each app's web UI and API, published on the host. The upstream defaults are:

| Service | Container port |
| --- | --- |
| Radarr | 7878 |
| Sonarr | 8989 |
| Lidarr | 8686 |
| Bazarr | 6767 |
| SABnzbd | 8080 |
| FlareSolverr | 8191 (used by the apps; needs no host port) |
| Recyclarr | none (no web UI) |

The 4K instances use the same container ports on different host ports; the mapping will be listed here
with `compose.yaml`.

## Volumes

| Mount | Host source | Used by |
| --- | --- | --- |
| `/config` | `$APPDATA_ROOT/<app>` | every app |
| `/data` | `$DATA_ROOT` | the apps that download, import or subtitle files |

No service mounts the Docker socket.

## Labels

| Label | Meaning |
| --- | --- |
| `org.honeybeartech.atlas.allow.<rule>` | Lets one service break one policy rule; the value is the reason, and must not be empty. Rules: `image`, `digest`, `latest`, `build`, `privileged`, `cap-add`, `host-network`, `host-pid`, `docker-socket` ([security.md](security.md#policy)). |

## Commands

| Command | Does |
| --- | --- |
| `docker compose up -d` / `down` / `ps` / `logs <service>` | Runs and inspects the stack |
| `make check` | `docker compose config --format json \| python scripts/check_compose.py`: the policy check |
| `python scripts/check_compose.py [FILE] [--sbom OUT]` | Checks a resolved Compose config (from `FILE` or stdin); `--sbom` also writes a CycloneDX 1.6 SBOM of the images. Exit 0 = no violations, 1 = violations (one line each), 2 = unreadable input |
| `make test`, `make lint` | The checker's tests and the linters |

## Outbound connections

From the host: the image registries (`lscr.io`, `ghcr.io`, Docker Hub) on `docker compose pull`. From the
apps: the indexers, the Usenet provider and metadata services they're configured for, and GitHub (Recyclarr
fetches the TRaSH Guides).

## Release files

Each GitHub Release has `homelab-atlas-<version>.tar.gz` (source, with `LICENSE`),
`homelab-atlas-<version>.cdx.json` (CycloneDX SBOM of the pinned images), `SHA256SUMS` and its Sigstore
bundle, and SLSA provenance ([verifying-releases.md](verifying-releases.md)).
